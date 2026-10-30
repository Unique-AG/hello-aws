import { config } from '../config';
import { decodeJwt } from '../auth/token';
import { gql, pollUntil } from './http';

/** Conduct (Swappable Intelligence) helpers, ported from the canonical suite's Conduct services. */

const MODULE_NAME = 'SwappableIntelligence';
const IN_FLIGHT_MESSAGE = 'Your previous message is still being processed.';
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// A cold sandbox (peer-pod VM boot or a Fargate image pull) can take minutes.
export const TURN_TIMEOUT_MS = 6 * 60_000;

export type ConductMessage = {
  id: string;
  text: string;
  role: string;
  completedAt: string | null;
  segmentKind: string | null;
  responseTurnId: string | null;
  debugInfo: Record<string, any> | null;
};

export type ConductTurn = {
  answer: ConductMessage;
  /** The turn's harness debugInfo; it can sit on a different segment than the answer text. */
  debugInfo: Record<string, any>;
};

// The tools the admin UI sends for a new Conduct space. All are ByUser, so none
// runs unless a turn selects it; code execution is built into the harness.
const DEFAULT_TOOLS = [
  {
    name: 'InternalSearch',
    displayName: 'Internal Search',
    icon: 'IconFolderData',
    isEnabled: true,
    isExclusive: false,
    selectionPolicy: 'ByUser',
    configuration: { scopeIds: [], searchType: 'COMBINED' },
    isSelectFilesToChatEnabled: false,
  },
  {
    name: 'WebSearch',
    displayName: 'Web Search',
    icon: 'IconWorld',
    isEnabled: true,
    isExclusive: false,
    selectionPolicy: 'ByUser',
    configuration: {},
    isSelectFilesToChatEnabled: false,
  },
  {
    name: 'Skill',
    displayName: 'Skills',
    icon: 'IconScrollText',
    isEnabled: true,
    isExclusive: false,
    selectionPolicy: 'ByUser',
    configuration: { selectableSkills: { sourceFolderId: null }, enableSkillCreation: true },
    isSelectFilesToChatEnabled: false,
  },
];

/** Create a Conduct space for the token's user from the deployment's defaults; CONDUCT_MODEL overrides the model. */
export async function createConductSpace(token: string, name: string): Promise<{ spaceId: string; model: string }> {
  const { configurationByAssistantType: typeConfig } = await gql(
    config.chatApiURL,
    token,
    `query ConfigurationByAssistantType($assistantType: AssistantUiType!) {
      configurationByAssistantType(assistantType: $assistantType) { advancedConfiguration }
    }`,
    { assistantType: 'SWAPPABLE_INTELLIGENCE' },
  );
  const defaults = structuredClone(typeConfig?.advancedConfiguration?.loopAgent?.defaultConfig);
  if (!defaults?.claude) {
    throw new Error('No Conduct default configuration; is assistants-core deployed with Conduct enabled?');
  }
  if (config.conductModel) defaults.claude.model = config.conductModel;
  const model: string = defaults.claude.model;

  const { moduleTemplates } = await gql(
    config.chatApiURL,
    token,
    `query ModuleTemplates($where: ModuleTemplateWhereInput) {
      moduleTemplates(where: $where) { id isExternal }
    }`,
    { where: { name: { equals: MODULE_NAME } } },
  );
  const template = moduleTemplates?.[0];
  if (!template) throw new Error(`No '${MODULE_NAME}' module template in this deployment.`);

  const userId = decodeJwt(token).sub;
  const data = await gql(
    config.chatApiURL,
    token,
    `mutation CreateAssistant($input: AssistantCreateInput!, $assistantAccessCreateInput: [AssistantAccessCreateDto!]) {
      createAssistant(input: $input, assistantAccessCreateInput: $assistantAccessCreateInput) { id }
    }`,
    {
      input: {
        name,
        alert: 'Automated smoke test space.',
        explanation: '',
        fallbackModule: MODULE_NAME,
        chatUpload: 'ENABLED',
        uiType: 'SWAPPABLE_INTELLIGENCE',
        isSubAgent: false,
        subAgentSettings: null,
        allowEndUserSpace: false,
        settings: {
          imageUpload: true,
          showPdfHighlighting: true,
          deviceAvailability: 'ALL_DEVICES',
          ingestionConfig: { uniqueIngestionMode: 'SKIP_INGESTION' },
        },
        modules: {
          create: [
            {
              name: MODULE_NAME,
              weight: 500,
              configuration: {
                ...defaults,
                strategy: 'claude_code',
                tools: structuredClone(DEFAULT_TOOLS),
                space: { ...defaults.space, projectName: name },
                languageModel: model,
              },
              toolDefinition: {},
              isCustomInstructionEnabled: false,
              isExternal: template.isExternal,
              moduleTemplate: { connect: { id: template.id } },
            },
          ],
        },
        userPrompts: { create: [] },
      },
      assistantAccessCreateInput: [
        { entityId: userId, entityType: 'USER', type: 'USE' },
        { entityId: userId, entityType: 'USER', type: 'MANAGE' },
      ],
    },
  );
  return { spaceId: data.createAssistant.id, model };
}

/** Send a user message; omit chatId to start a new chat. Returns the chat id. */
export async function sendMessage(token: string, spaceId: string, text: string, chatId?: string): Promise<string> {
  const data = await gql(
    config.chatApiURL,
    token,
    `mutation MessageCreate($chatId: String, $assistantId: String, $input: MessageCreateInput!) {
      messageCreate(chatId: $chatId, assistantId: $assistantId, input: $input) { chatId }
    }`,
    { chatId, assistantId: spaceId, input: { text, role: 'USER' } },
  );
  return data.messageCreate.chatId;
}

async function getMessages(token: string, chatId: string): Promise<ConductMessage[]> {
  const data = await gql(
    config.chatApiURL,
    token,
    `query PaginatedMessage($chatId: String!, $take: Int, $orderBy: [MessageOrderByWithRelationInput!]) {
      paginatedMessage(chatId: $chatId, take: $take, orderBy: $orderBy) {
        nodes { id text role completedAt segmentKind responseTurnId debugInfo }
      }
    }`,
    { chatId, take: 20, orderBy: [{ createdAt: 'desc' }] },
  );
  return data.paginatedMessage?.nodes ?? [];
}

/** Wait for the next completed turn, ignoring messages in `after`; done once the harness writes its timings. */
export async function waitForTurn(
  token: string,
  chatId: string,
  { after = [] as string[], timeoutMs = TURN_TIMEOUT_MS } = {},
): Promise<ConductTurn> {
  const result = await pollUntil(
    async () => {
      const done = (await getMessages(token, chatId)).filter(
        (m) => m.role === 'ASSISTANT' && m.completedAt && !after.includes(m.id),
      );
      // A turn refused while the chat is locked has no harness run; followUpTurn resends it.
      const refused = done.find((m) => m.text?.includes(IN_FLIGHT_MESSAGE));
      if (refused) return { state: 'refused as in flight', turn: { answer: refused, debugInfo: {} } };
      const ready = done.find((m) => (m.debugInfo?.timings_ms?.agent_loop_ms ?? 0) > 0);
      if (!ready) {
        const latest = done[0]?.text?.trim().slice(0, 300) ?? '';
        return { state: `${done.length} completed assistant message(s), no harness timings yet; latest: ${latest}` };
      }
      const answer =
        done.find(
          (m) => m.responseTurnId === ready.responseTurnId && m.segmentKind === 'ANSWER' && m.text?.trim(),
        ) ?? ready;
      return { state: 'done', turn: { answer, debugInfo: ready.debugInfo! } };
    },
    (v) => v.turn !== undefined,
    { timeoutMs, intervalMs: 3000, label: 'a completed Conduct turn' },
  );
  return result.turn!;
}

/** Start a chat in a Conduct space and wait for its first turn. */
export async function firstTurn(token: string, spaceId: string, prompt: string): Promise<ConductTurn & { chatId: string }> {
  const chatId = await sendMessage(token, spaceId, prompt);
  return { chatId, ...(await waitForTurn(token, chatId)) };
}

/** Send a follow-up turn, resending while Conduct refuses it because the previous turn holds the chat lock. */
export async function followUpTurn(token: string, spaceId: string, chatId: string, prompt: string): Promise<ConductTurn> {
  for (let attempt = 1; attempt <= 3; attempt++) {
    await sleep(5000);
    const after = (await getMessages(token, chatId)).filter((m) => m.role === 'ASSISTANT').map((m) => m.id);
    await sendMessage(token, spaceId, prompt, chatId);
    const turn = await waitForTurn(token, chatId, { after });
    if (!turn.answer.text.includes(IN_FLIGHT_MESSAGE)) return turn;
  }
  throw new Error('Conduct follow-up turn was still rejected as in flight after 3 attempts.');
}

/** Number of tool calls the harness made in a turn (code execution counts). */
export const toolCallCount = (turn: ConductTurn): number => Number(turn.debugInfo.tool_call_count ?? 0);

/** A generated file Conduct attaches to an answer as a fenced fileWithSource block. */
export function parseFileBlock(text: string): { contentId: string; title: string } | undefined {
  const block = text.match(/```(?:fileWithSource|imgWithSource|htmlWithSource)\n([\s\S]*?)\n```/)?.[1];
  if (!block) return undefined;
  return {
    contentId: block.match(/contentId='([^']+)'/)?.[1] ?? '',
    title: block.match(/title="((?:[^"\\]|\\.)*)"/)?.[1] ?? '',
  };
}

/** Best-effort cleanup of chats; logs instead of throwing, like deleteAssistant. */
export async function deleteChats(token: string, chatIds: string[]): Promise<void> {
  if (chatIds.length === 0) return;
  await gql(
    config.chatApiURL,
    token,
    `mutation ChatDeleteByChatIds($chatIds: [String!]!) { chatDeleteByChatIds(chatIds: $chatIds) { id } }`,
    { chatIds },
  ).catch((e) => {
    console.warn(`deleteChats(${chatIds.join(',')}) cleanup failed: ${e}`);
  });
}
