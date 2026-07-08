import { test, expect } from '@playwright/test';
import { fileURLToPath } from 'node:url';
import { config } from '../../../config';
import { getBrowserUserToken } from '../../../auth/token';
import { createFolder, deleteScope } from '../../../lib/ingestion';

const SEED = fileURLToPath(new URL('../../../resources/exampleText.txt', import.meta.url));

/**
 * UI file upload into a fresh KB folder. The folder is created with the browser
 * user's own token (from the saved session) so that user can see/open it in the
 * UI — creating it as the service user causes a 403 in the browser.
 */
test('@smoke browser — upload a file in Knowledge Base', async ({ page }) => {
  const token = getBrowserUserToken();
  const scopeId = await createFolder(token, `smoke-kb-${Date.now()}`);
  try {
    await page.goto(`${config.knowledgeUploadAppURL}/${scopeId}`);
    await page.waitForLoadState('networkidle');

    const uploadButton = page.getByRole('button').filter({ hasText: 'Upload Files' });
    const fileInput = uploadButton.locator('input[type="file"]');
    await fileInput.setInputFiles(SEED);

    await expect(page.getByText('Upload Completed!').first()).toBeVisible({ timeout: 120_000 });
  } finally {
    await deleteScope(token, scopeId);
  }
});
