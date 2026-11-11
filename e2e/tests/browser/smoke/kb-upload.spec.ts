import { test, expect } from '@playwright/test';
import { config } from '../../../config';
import { getBrowserUserToken } from '../../../auth/token';
import { createFolder, deleteScope } from '../../../lib/ingestion';
import { seedFile } from '../../../lib/resources';

const SEED = seedFile('exampleText.txt');

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

    // Wait on the control, not networkidle: this app never reaches that state, so
    // the bare wait spent the whole test budget and reported no cause.
    const uploadButton = page.getByRole('button').filter({ hasText: 'Upload Files' });
    await expect(uploadButton, 'the Knowledge Upload app should render its upload control')
      .toBeVisible({ timeout: 30_000 });
    const fileInput = uploadButton.locator('input[type="file"]');
    await fileInput.setInputFiles(SEED);

    // Loose on purpose: the toast copy moves with FEATURE_FLAG_ENABLE_TOAST_V2_UN_23011,
    // so a failure here means changed wording, not broken ingestion.
    await expect(page.getByText(/upload\s*complet/i).first()).toBeVisible({ timeout: 60_000 });
  } finally {
    await deleteScope(token, scopeId);
  }
});
