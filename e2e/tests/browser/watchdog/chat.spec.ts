import { test, expect } from '@playwright/test';
import { config } from '../../../config';

/**
 * Simple chat round-trip in the default chat. Assumes the tenant has a
 * chattable default space; if not, this fails loudly — a signal to seed one.
 * Selectors are from the canonical suite's chat page object.
 */
test('@watchdog browser — simple chat returns an answer', async ({ page }) => {
  await page.goto(config.chatAppURL);

  const input = page.getByTestId('chat-text-field');
  await expect(input).toBeVisible({ timeout: 30_000 });
  await input.fill('What is 2+2=? Provide in output only result in number format.');
  await page.getByTestId('send-message-button').click();

  const answer = page.getByTestId('answer-1');
  await expect(answer).toBeVisible({ timeout: 60_000 });
  await expect(answer).toContainText('4', { timeout: 60_000 });
});
