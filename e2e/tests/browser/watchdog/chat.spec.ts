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
  // Wait for the streamed answer to settle: non-empty and unchanged for ~1s.
  // (Asserting the exact token "4" is too brittle for non-deterministic LLM output.)
  await expect(async () => {
    const first = (await answer.innerText()).trim();
    expect(first.length, 'assistant answer should be non-empty').toBeGreaterThan(0);
    await page.waitForTimeout(1000);
    const second = (await answer.innerText()).trim();
    expect(second, 'answer should stop streaming').toBe(first);
  }).toPass({ timeout: 60_000 });
  // Assert on the settled answer, so an error that streams in late still fails.
  await expect(answer).not.toContainText(/unexpected error/i);
});
