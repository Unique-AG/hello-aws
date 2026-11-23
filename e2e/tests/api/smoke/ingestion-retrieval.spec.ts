import { test, expect } from '@playwright/test';
import { getServiceUserToken } from '../../../auth/token';
import { deleteAssistant } from '../../../lib/chat';
import { createFolder, uploadFileToKB, waitForIngestionFinished, deleteScope } from '../../../lib/ingestion';
import { TURN_TIMEOUT_MS, createConductSpace, deleteChats, firstTurn } from '../../../lib/conduct';

/**
 * Reading a chunk back by contentId only proves the relational store. This asks
 * the retrieval path for it instead, which is the one place the search indexes
 * are reachable from outside the cluster.
 *
 * Scope: InternalSearch runs `searchType: COMBINED` — vector and full text
 * together — so a pass proves retrieval works, not that Elasticsearch
 * specifically served it. There is no search query on the ingestion or chat
 * GraphQL APIs to narrow it further.
 */

// A value no model can have been trained on, so an answer containing it was
// retrieved rather than recalled.
const NONCE = `uq${Date.now().toString(36)}${Math.random().toString(36).slice(2, 10)}`;
const DOC = `Ingestion retrieval probe.\n\nThe ingestion probe identifier is ${NONCE}.\n`;

test.describe.serial('@smoke API ingestion — retrieval', () => {
  let token: string;
  let scopeId: string | undefined;
  let spaceId: string | undefined;
  const chatIds: string[] = [];

  test.beforeAll(async () => {
    token = await getServiceUserToken();
  });

  test.afterAll(async () => {
    await deleteChats(token, chatIds);
    if (spaceId) await deleteAssistant(token, spaceId);
    if (scopeId) await deleteScope(token, scopeId);
  });

  test('an ingested document can be retrieved by its content', async () => {
    test.setTimeout(TURN_TIMEOUT_MS + 180_000);

    scopeId = await createFolder(token, `smoke-retrieval-${Date.now()}`);
    const contentId = await uploadFileToKB(token, scopeId, {
      key: `retrieval-probe-${NONCE}.txt`,
      mimeType: 'text/plain',
      bytes: Buffer.from(DOC, 'utf8'),
    });

    const content = await waitForIngestionFinished(token, contentId, 120_000);
    expect(content.ingestionState).toBe('FINISHED');

    ({ spaceId } = await createConductSpace(token, `smoke-retrieval-${Date.now()}`));
    // InternalSearch is selected by the turn, not always on, so the prompt has
    // to ask for a knowledge-base search outright.
    const turn = await firstTurn(
      token,
      spaceId,
      'Search the knowledge base for the document titled "Ingestion retrieval probe" ' +
        'and reply with the ingestion probe identifier it contains, and nothing else.',
    );
    chatIds.push(turn.chatId);

    expect(turn.answer.text, 'the assistant should answer').toBeTruthy();
    // Only the index can supply this, so its presence is the retrieval proof.
    expect(turn.answer.text).toContain(NONCE);
  });
});
