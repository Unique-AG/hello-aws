import { test as setup, expect, type Locator } from '@playwright/test';
import fs from 'node:fs';
import { config, AUTH_FILE } from '../config';
import { appChromeReady } from '../lib/ui';

/**
 * Interactive OIDC login against Zitadel's v2 login UI, then persist the
 * session so browser tests reuse it. Tolerant of the optional 2FA and terms
 * prompts that only appear on a first login.
 */
// Tags @watchdog @smoke so it is never filtered out by `--grep` — the browser
// projects depend on it, so it must run for every tier.
/**
 * True once the locator is visible, false if it never appears. isVisible() does
 * not wait — it ignores its timeout — so an optional prompt guarded with it is
 * skipped whenever it has not rendered in that instant.
 */
const appeared = (locator: Locator, timeout = 5_000): Promise<boolean> =>
  locator
    .waitFor({ state: 'visible', timeout })
    .then(() => true)
    .catch(() => false);

setup('Authenticate single user @watchdog @smoke', async ({ page }) => {
  fs.mkdirSync('.auth', { recursive: true });

  await page.goto(config.chatAppURL);

  // The v2 login UI is a separate app served at /ui/v2/login, reached by the
  // authorize redirect. Its fields carry data-testid, so the selectors survive
  // copy changes and a non-English instance; the legacy login had neither.
  const loginName = page.getByTestId('username-text-input');
  await expect(
    loginName,
    'the Zitadel login form should render — a 404 here means the login UI is not deployed',
  ).toBeVisible({ timeout: 30_000 });
  // The login UI is a Next.js app: a value set before hydration is wiped when
  // React re-renders from its own empty state, leaving submit disabled forever.
  // Type with real key events, then prove the value stuck before clicking.
  await page.waitForLoadState('networkidle').catch(() => {});
  await loginName.click();
  await loginName.pressSequentially(config.user.username, { delay: 10 });
  await expect(loginName).toHaveValue(config.user.username, { timeout: 10_000 });

  const loginNameSubmit = page.getByTestId('submit-button');
  await expect(loginNameSubmit, 'submit should enable once the loginname registers').toBeEnabled({
    timeout: 10_000,
  });
  await loginNameSubmit.click();

  // The password step renders only once the loginname resolves to a user, so
  // its absence is how a wrong TEST_USER surfaces. Report whatever the page
  // says rather than matching one localised error string.
  const passwordField = page.getByTestId('password-text-input');
  // waitFor, not isVisible: isVisible resolves immediately and ignores its
  // timeout, so it reports failure before the submit has even landed.
  try {
    await passwordField.waitFor({ state: 'visible', timeout: 30_000 });
  } catch {
    const shown = (await page.locator('body').innerText().catch(() => ''))
      .replace(/\s+/g, ' ')
      .trim();
    throw new Error(
      `Zitadel did not accept loginname "${config.user.username}". ` +
        `TEST_USER must be an existing loginname in the customer organization. ` +
        `Page showed: ${shown.slice(0, 300)}`,
    );
  }

  await passwordField.click();
  await passwordField.pressSequentially(config.user.password, { delay: 10 });
  await expect(passwordField).toHaveValue(config.user.password, { timeout: 10_000 });

  const passwordSubmit = page.getByTestId('submit-button');
  await expect(passwordSubmit).toBeEnabled({ timeout: 10_000 });
  await passwordSubmit.click();

  // Optional: skip 2FA setup prompt.
  const twoFa = page.getByRole('heading', { name: /2-Factor|Two-Factor|MFA/i });
  if (await appeared(twoFa, 3_000)) {
    await page.getByRole('button', { name: /Skip/i }).click();
  }

  // Optional: accept terms on first login.
  const terms = page.getByText('I have read and I agree to');
  if (await appeared(terms, 3_000)) {
    await page.getByRole('checkbox').first().check();
    await page.getByRole('button', { name: 'Agree' }).click();
  }

  // Back on the app host and app chrome is ready (either nav variant).
  const appHost = new URL(config.chatAppURL).hostname;
  await page.waitForURL((url) => url.hostname === appHost, { timeout: 30_000 });

  await expect(appChromeReady(page)).toBeVisible({ timeout: 30_000 });

  // First-login in-app Terms & Conditions modal (distinct from the Zitadel one):
  // accept it so it persists server-side and never blocks the chat UI.
  const tcAgree = page.getByRole('checkbox', { name: /I have read and I agree to the Terms/i });
  if (await appeared(tcAgree, 15_000)) {
    await tcAgree.check();
    await page.getByRole('button', { name: 'Agree' }).click();
    await expect(tcAgree).toBeHidden({ timeout: 10_000 });
  }

  await page.context().storageState({ path: AUTH_FILE });
});
