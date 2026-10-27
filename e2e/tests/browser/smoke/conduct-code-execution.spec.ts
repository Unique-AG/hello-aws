import { test, expect } from '@playwright/test';
import { config } from '../../../config';
import { getBrowserUserToken } from '../../../auth/token';
import { deleteAssistant } from '../../../lib/chat';
import { TURN_TIMEOUT_MS, createConductSpace } from '../../../lib/conduct';

// The space is created with the browser user's token so that user can open it.
// Card test ids are from the canonical suite's code-execution page object.
test('@smoke @conduct browser — Conduct renders a code-execution card', async ({ page }) => {
  test.setTimeout(TURN_TIMEOUT_MS + 2 * 60_000);
  const token = getBrowserUserToken();
  const { spaceId } = await createConductSpace(token, `smoke-conduct-ui-${Date.now()}`);
  try {
    await page.goto(`${config.chatAppURL}/space/${spaceId}`);

    const input = page.getByTestId('chat-text-field');
    await expect(input).toBeVisible({ timeout: 30_000 });
    await input.fill(
      'Using code execution, create a UTF-8 text file named "conduct-ce-smoke.txt" containing exactly ' +
        '"conduct ce smoke ready" with no extra text in the file. Return only the generated file and ' +
        'create no other files.',
    );
    await page.getByTestId('send-message-button').click();

    const answer = page.getByTestId('answer-1');
    await expect(answer.getByTestId('code-exec-content-switch').first()).toBeVisible({ timeout: TURN_TIMEOUT_MS });
    await expect(answer.getByTestId('code-exec-code-switch').first()).toBeVisible();
    await expect(answer).not.toContainText(/unexpected error/i);
  } finally {
    await deleteAssistant(token, spaceId);
  }
});
