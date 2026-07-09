import { test, expect } from '@playwright/test';
import { config } from '../../../config';
import { appChromeReady } from '../../../lib/ui';

test('@watchdog browser — session is authenticated and app loads', async ({ page }) => {
  await page.goto(config.chatAppURL);

  // App chrome is present under either nav variant → we're logged in.
  await expect(appChromeReady(page)).toBeVisible({ timeout: 30_000 });
});
