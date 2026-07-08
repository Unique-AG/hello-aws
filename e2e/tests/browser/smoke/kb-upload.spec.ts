import { test, expect } from '@playwright/test';
import { fileURLToPath } from 'node:url';
import { config } from '../../../config';
import { getServiceUserToken } from '../../../auth/token';
import { createFolder, deleteScope } from '../../../lib/ingestion';

const SEED = fileURLToPath(new URL('../../../resources/exampleText.txt', import.meta.url));

/**
 * UI file upload into a fresh KB folder.
 * NOTE: the folder is created via API then opened in the UI; the upload control
 * + success-toast selectors may need adjustment on the first live run. If the
 * browser user can't see an API-created scope, create the folder in the UI too.
 */
test('@smoke browser — upload a file in Knowledge Base', async ({ page }) => {
  const token = await getServiceUserToken();
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
