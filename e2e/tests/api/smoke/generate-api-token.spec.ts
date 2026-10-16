import { test, expect } from '@playwright/test';
import { getServiceUserToken, getUserIdFromToken, getCompanyIdFromToken } from '../../../auth/token';
import { createPersonalAPIKey, getCompanyAcronyms } from '../../../lib/apps';

test('@smoke API — generate a personal API key and call the public SDK', async () => {
  const token = await getServiceUserToken();

  const { appId, apiKey } = await createPersonalAPIKey(token);
  expect(appId, 'app id').toBeTruthy();
  expect(apiKey, 'api key').toBeTruthy();

  const status = await getCompanyAcronyms({
    userId: getUserIdFromToken(token),
    companyId: getCompanyIdFromToken(token),
    appId,
    apiKey,
  });
  expect(status).toBe(200);
});
