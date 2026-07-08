import { test, expect } from '@playwright/test';
import { config } from '../../../config';

test('@watchdog browser — session is authenticated and app loads', async ({ page }) => {
  await page.goto(config.chatAppURL);

  // App chrome is present under either nav variant → we're logged in.
  const chatInput = page.getByTestId('chat-text-field');
  const spacesNav = page.getByRole('link', { name: 'Spaces', exact: true });
  const exploreSpaces = page.getByRole('button', { name: 'Explore Spaces', exact: true });
  await expect(chatInput.or(spacesNav).or(exploreSpaces).first()).toBeVisible({ timeout: 30_000 });
});
