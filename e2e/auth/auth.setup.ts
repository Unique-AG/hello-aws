import { test as setup, expect } from '@playwright/test';
import fs from 'node:fs';
import { config } from '../config';

const AUTH_FILE = '.auth/user.json';

/**
 * Interactive OIDC login against the Zitadel hosted form, then persist the
 * session so browser tests reuse it. Ported from the canonical suite's
 * authenticateUser(); tolerant of the two nav variants + optional 2FA/terms.
 */
// Tags @watchdog @smoke so it is never filtered out by `--grep` — the browser
// projects depend on it, so it must run for every tier.
setup('Authenticate single user @watchdog @smoke', async ({ page }) => {
  fs.mkdirSync('.auth', { recursive: true });

  await page.goto(config.chatAppURL);

  // Zitadel hosted login: username → Next → password → Next.
  await page.getByPlaceholder('username').fill(config.user.username);
  await page.getByRole('button', { name: 'Next' }).click();

  // Fail loudly + fast if the loginname isn't recognised (wrong user/org).
  const notFound = page.getByText('User could not be found');
  const passwordField = page.locator('input[type="password"]');
  await expect(
    passwordField.or(notFound).first(),
    'password field should appear after entering the loginname',
  ).toBeVisible({ timeout: 15_000 });
  if (await notFound.isVisible().catch(() => false)) {
    throw new Error(
      `Zitadel rejected loginname "${config.user.username}" (User could not be found). ` +
        `TEST_USER must be an existing loginname in the Unique organization.`,
    );
  }

  await passwordField.fill(config.user.password);
  await page.getByRole('button', { name: 'Next' }).click();

  // Optional: skip 2FA setup prompt.
  const twoFa = page.getByRole('heading', { name: '2-Factor Setup' });
  if (await twoFa.isVisible({ timeout: 3000 }).catch(() => false)) {
    await page.getByRole('button', { name: 'Skip' }).click();
  }

  // Optional: accept terms on first login.
  const terms = page.getByText('I have read and I agree to');
  if (await terms.isVisible({ timeout: 3000 }).catch(() => false)) {
    await page.getByRole('checkbox').first().check();
    await page.getByRole('button', { name: 'Agree' }).click();
  }

  // Back on the app host and app chrome is ready (either nav variant).
  const appHost = new URL(config.chatAppURL).hostname;
  await page.waitForURL((url) => url.hostname === appHost, { timeout: 30_000 });

  const chatInput = page.getByTestId('chat-text-field');
  const spacesNav = page.getByRole('link', { name: 'Spaces', exact: true });
  const exploreSpaces = page.getByRole('button', { name: 'Explore Spaces', exact: true });
  await expect(chatInput.or(spacesNav).or(exploreSpaces).first()).toBeVisible({ timeout: 30_000 });

  // First-login in-app Terms & Conditions modal (distinct from the Zitadel one):
  // accept it so it persists server-side and never blocks the chat UI.
  const tcAgree = page.getByRole('checkbox', { name: /I have read and I agree to the Terms/i });
  if (await tcAgree.isVisible({ timeout: 5_000 }).catch(() => false)) {
    await tcAgree.check();
    await page.getByRole('button', { name: 'Agree' }).click();
    await expect(tcAgree).toBeHidden({ timeout: 10_000 });
  }

  await page.context().storageState({ path: AUTH_FILE });
});
