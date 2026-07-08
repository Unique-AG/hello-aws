import { test, expect } from '@playwright/test';
import { config } from '../../../config';

/**
 * UI Space V2 creation.
 * NOTE: the space-type selection step is a best-effort port and is the most
 * likely selector to need adjustment on the first live run.
 */
test('@smoke browser — create a Space V2', async ({ page }) => {
  const spaceName = `smoke-space-${Date.now()}`;
  await page.goto(`${config.adminAppURL}/space/create`);
  await page.waitForLoadState('networkidle');

  // Choose the "Unique AI" space type.
  await page.getByText('Unique AI', { exact: false }).first().click();

  await page.getByPlaceholder('Name').fill(spaceName);

  const createButton = page.getByRole('button', { name: /create( space)?/i }).last();
  const [resp] = await Promise.all([
    page.waitForResponse(
      (r) => r.url().includes('/chat/graphql') && r.request().method() === 'POST' && r.status() === 200,
      { timeout: 30_000 },
    ),
    createButton.click(),
  ]);
  const body = await resp.json();
  expect(body?.data?.createAssistant?.id, 'created assistant id').toBeTruthy();
});
