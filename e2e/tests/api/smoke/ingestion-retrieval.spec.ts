import { test, expect } from '@playwright/test';
import { getServiceUserToken, getUserIdFromToken, getCompanyIdFromToken } from '../../../auth/token';
import { createPersonalAPIKey } from '../../../lib/apps';
import { createFolder, uploadFileToKB, waitForIngestionFinished, deleteScope } from '../../../lib/ingestion';
import { search, type PublicApiCaller, type SearchType } from '../../../lib/search';

/**
 * Reading a chunk back by contentId only proves the relational store. This asks
 * the search endpoint for it instead, once per index, so a failure names the
 * store that lost the document rather than just "search".
 */

// A value no model can have been trained on and no other test will write, so a
// hit is this document and nothing else.
const NONCE = `uq${Date.now().toString(36)}${Math.random().toString(36).slice(2, 10)}`;
const DOC = `Ingestion retrieval probe.\n\nThe ingestion probe identifier is ${NONCE}.\n`;

// Not serial: in serial mode a FULL_TEXT failure skips VECTOR, which is exactly
// the comparison this test exists to make. beforeAll re-seeds per worker.
test.describe('@smoke API ingestion — retrieval', () => {
  let caller: PublicApiCaller;
  let scopeId: string | undefined;
  let token: string;

  test.beforeAll(async () => {
    token = await getServiceUserToken();
    const { appId, apiKey } = await createPersonalAPIKey(token);
    caller = { appId, apiKey, userId: getUserIdFromToken(token), companyId: getCompanyIdFromToken(token) };

    scopeId = await createFolder(token, `smoke-retrieval-${Date.now()}`);
    const contentId = await uploadFileToKB(token, scopeId, {
      key: `retrieval-probe-${NONCE}.txt`,
      mimeType: 'text/plain',
      bytes: Buffer.from(DOC, 'utf8'),
    });
    const content = await waitForIngestionFinished(token, contentId, 120_000);
    expect(content.ingestionState).toBe('FINISHED');
  });

  test.afterAll(async () => {
    if (scopeId) await deleteScope(token, scopeId);
  });

  // FULL_TEXT is the full-text store and VECTOR the vector store; running both
  // separately is what makes one broken index distinguishable from the other.
  for (const searchType of ['FULL_TEXT', 'VECTOR'] as SearchType[]) {
    test(`the ingested document is returned by ${searchType} search`, async () => {
      const { status, hits, raw } = await search(caller, {
        searchString: `ingestion probe identifier ${NONCE}`,
        searchType,
        scopeIds: scopeId ? [scopeId] : undefined,
      });

      // The endpoint answers 201, not 200; assert the class, not the code.
      expect(status, `${searchType} search should succeed: ${raw.slice(0, 200)}`).toBeLessThan(300);
      expect(status, `${searchType} search should succeed: ${raw.slice(0, 200)}`).toBeGreaterThanOrEqual(200);
      expect(hits.length, `${searchType} search returned no hits`).toBeGreaterThan(0);
      expect(
        hits.some((h) => h.text?.includes(NONCE)),
        `no ${searchType} hit contained the probe identifier`,
      ).toBe(true);
    });
  }
});
