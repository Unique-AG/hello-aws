import { test, expect } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { getServiceUserToken } from '../../../auth/token';
import { createFolder, uploadFileToKB, waitForIngestionFinished, getFirstChunk, deleteScope } from '../../../lib/ingestion';
import { seedFile } from '../../../lib/resources';

const SEED = seedFile('exampleText.txt');

test('@watchdog API ingestion — upload a .txt and verify chunk content', async () => {
  const token = await getServiceUserToken();
  const scopeId = await createFolder(token, `wd-ingest-${Date.now()}`);
  const fileName = 'exampleText.txt';
  try {
    const contentId = await uploadFileToKB(token, scopeId, {
      key: fileName,
      mimeType: 'text/plain',
      bytes: readFileSync(SEED),
    });

    const content = await waitForIngestionFinished(token, contentId, 90_000);
    expect(content.ingestionState).toBe('FINISHED');

    const chunk = await getFirstChunk(token, contentId);
    expect(chunk?.text, 'ingested chunk should have text').toBeTruthy();
    // The chunk is wrapped in <|document|>…<|/document|> markers by the pipeline.
    expect(chunk.text.startsWith('<|document|>')).toBeTruthy();
    // Content of resources/exampleText.txt must survive ingestion verbatim.
    expect(chunk.text).toContain('Brad Pit is an actor.');
    expect(chunk.text).toContain('Joseph Biden is an American president.');
    expect(chunk.text).toContain('Nikola Jokic is famous basketball player.');
  } finally {
    await deleteScope(token, scopeId);
  }
});
