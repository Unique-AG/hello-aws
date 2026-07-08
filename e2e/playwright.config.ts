import { defineConfig, devices } from '@playwright/test';
import { config } from './config';

/**
 * Two surfaces, two tiers:
 *   - projects `browser` (Chromium UI) and `api` (no browser)
 *   - tag tests @watchdog (critical path) or @smoke (broader) and filter with
 *     `--grep` (see package.json scripts).
 *
 * The `setup` project performs the interactive OIDC login once and saves a
 * storageState that the `browser` project reuses. `api` tests mint their own
 * service-user token per run and need no stored session.
 */
export default defineConfig({
  testDir: './tests',
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  // Always serial: the suite runs against one shared tenant with a single test
  // user, so parallel workers would race the same session/spaces.
  workers: 1,
  timeout: 2 * 60 * 1000,
  reporter: process.env.CI
    ? [['html', { open: 'never' }], ['list']]
    : [['list']],
  use: {
    baseURL: config.baseURL,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    viewport: { width: 1920, height: 1080 },
  },
  projects: [
    {
      name: 'setup',
      testDir: './auth',
      testMatch: /auth\.setup\.ts/,
    },
    {
      name: 'browser',
      testDir: './tests/browser',
      use: { ...devices['Desktop Chrome'], storageState: '.auth/user.json' },
      dependencies: ['setup'],
    },
    {
      name: 'api',
      testDir: './tests/api',
    },
  ],
});
