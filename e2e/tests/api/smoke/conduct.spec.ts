import { test, expect } from '@playwright/test';
import { getServiceUserToken } from '../../../auth/token';
import { deleteAssistant } from '../../../lib/chat';
import { contentById } from '../../../lib/ingestion';
import {
  TURN_TIMEOUT_MS,
  createConductSpace,
  deleteChats,
  firstTurn,
  followUpTurn,
  parseFileBlock,
  toolCallCount,
} from '../../../lib/conduct';

// Each check needs code to really execute, so it passes only when a sandbox ran the agent's tools.
// The tests share one space; the first turn may wait for a cold sandbox.
test.describe.serial('@smoke @conduct API — Conduct sandbox', () => {
  let token: string;
  let spaceId: string | undefined;
  let model: string;
  const chatIds: string[] = [];

  test.beforeAll(async () => {
    token = await getServiceUserToken();
    ({ spaceId, model } = await createConductSpace(token, `smoke-conduct-${Date.now()}`));
  });

  test.afterAll(async () => {
    await deleteChats(token, chatIds);
    if (spaceId) await deleteAssistant(token, spaceId);
  });

  test('code runs in the sandbox and its output comes back', async () => {
    test.setTimeout(TURN_TIMEOUT_MS + 60_000);
    // The digest is not in the prompt, so it can only come from executed code.
    const turn = await firstTurn(
      token,
      spaceId!,
      'Using code execution, compute the lowercase SHA-256 hex digest of the exact ASCII string ' +
        '"conduct-ce-stdout" (no quotes, no trailing newline), print only that digest to stdout, and ' +
        'include the printed digest verbatim in your final response.',
    );
    chatIds.push(turn.chatId);

    expect(turn.answer.text).toContain('c78d75048b21081709b8fc56813f05a129fca684048879124dfe4b8cf94d4ed4');
    expect(toolCallCount(turn), 'the harness should report tool calls').toBeGreaterThan(0);
    expect(turn.debugInfo.model, 'the turn should run on the space model').toBe(model);
  });

  test('the workspace persists across turns', async () => {
    test.setTimeout(2 * TURN_TIMEOUT_MS + 60_000);
    const marker = `CONDUCT_WORKSPACE_MARKER_${Date.now()}`;
    const first = await firstTurn(
      token,
      spaceId!,
      'Use your file tools to create continuity-marker.txt in the workspace. ' +
        `The file must contain exactly: ${marker} ` +
        'Do not only describe the action. Write the file, then confirm completion.',
    );
    chatIds.push(first.chatId);
    expect(toolCallCount(first), 'the first turn should write the file').toBeGreaterThan(0);

    const second = await followUpTurn(
      token,
      spaceId!,
      first.chatId,
      'Read continuity-marker.txt from the existing workspace and reply with only its exact contents.',
    );
    expect(second.answer.text).toContain(marker);
  });

  test('a generated file is stored and linked in the answer', async () => {
    test.setTimeout(TURN_TIMEOUT_MS + 60_000);
    const fileName = 'conduct-ce-smoke.txt';
    const turn = await firstTurn(
      token,
      spaceId!,
      `Using code execution, create a UTF-8 text file named "${fileName}" containing exactly ` +
        '"conduct ce smoke ready" with no extra text in the file. Return only the generated file and ' +
        'create no other files.',
    );
    chatIds.push(turn.chatId);

    const file = parseFileBlock(turn.answer.text);
    expect(file, 'the answer should carry a generated-file block').toBeDefined();
    expect(file!.title).toBe(fileName);
    const content = await contentById(token, file!.contentId);
    // 22 bytes as asked, or 23 if the agent ends the file with a newline.
    expect([22, 23], 'the stored file should hold the written text').toContain(content?.byteSize);
  });
});
