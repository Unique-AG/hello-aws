import { config } from '../config';
import { gql } from './http';

const API_VERSION = '2023-12-06';

/** Create a personal API key (app-scoped) for the current service user. */
export async function createPersonalAPIKey(token: string): Promise<{ appId: string; apiKey: string }> {
  const data = await gql(
    config.appsApiURL,
    token,
    `mutation AppCreateWithUserScope { appCreateWithUserScope { key app { id } } }`,
  );
  return { appId: data.appCreateWithUserScope.app.id, apiKey: data.appCreateWithUserScope.key };
}

/** Call a public-SDK endpoint with an app API key. Returns the HTTP status. */
export async function getCompanyAcronyms(args: {
  userId: string;
  companyId: string;
  appId: string;
  apiKey: string;
}): Promise<number> {
  const res = await fetch(`${config.publicSdkURL}/company/acronyms`, {
    method: 'GET',
    headers: {
      Accept: '*/*',
      'Content-Type': 'application/json',
      'x-api-version': API_VERSION,
      'x-company-id': args.companyId,
      'x-user-id': args.userId,
      'x-app-id': args.appId,
      Authorization: `Bearer ${args.apiKey}`,
    },
  });
  return res.status;
}
