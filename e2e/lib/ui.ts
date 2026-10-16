import { type Page, type Locator } from '@playwright/test';

/**
 * Locator that resolves once the app chrome has loaded under either nav variant
 * (chat input, side-menu "Spaces", or legacy "Explore Spaces") — i.e. we're
 * logged in and the SPA is ready. Shared by the auth setup and the session test
 * since it's the most selector-fragile assertion in the suite.
 */
export function appChromeReady(page: Page): Locator {
  const chatInput = page.getByTestId('chat-text-field');
  const spacesNav = page.getByRole('link', { name: 'Spaces', exact: true });
  const exploreSpaces = page.getByRole('button', { name: 'Explore Spaces', exact: true });
  return chatInput.or(spacesNav).or(exploreSpaces).first();
}
