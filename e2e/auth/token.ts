import { readFileSync } from 'node:fs';
import { config, AUTH_FILE } from '../config';
import { postForm } from '../lib/http';

/**
 * Service-user auth via OAuth2 client_credentials against Zitadel.
 * Mirrors the canonical suite's api/services/auth.ts token exchange.
 */
export async function getServiceUserToken(): Promise<string> {
  const scope = [
    'openid',
    'profile',
    'email',
    'urn:zitadel:iam:user:resourceowner',
    'urn:zitadel:iam:org:projects:roles',
    `urn:zitadel:iam:org:project:id:${config.zitadelProjectId}:aud`,
  ].join(' ');

  const basic = Buffer.from(
    `${config.serviceUser.clientId}:${config.serviceUser.clientSecret}`,
  ).toString('base64');

  const json = await postForm(
    `${config.zitadelDomain}/oauth/v2/token`,
    { grant_type: 'client_credentials', scope },
    { Authorization: `Basic ${basic}` },
  );
  if (!json.access_token) throw new Error(`Token response had no access_token: ${JSON.stringify(json)}`);
  return json.access_token as string;
}

/** Decode a JWT payload (no signature verification — for reading claims only). */
export function decodeJwt(token: string): Record<string, any> {
  const payload = token.split('.')[1];
  return JSON.parse(Buffer.from(payload, 'base64').toString('utf8'));
}

export const getUserIdFromToken = (t: string): string => decodeJwt(t).sub;
export const getCompanyIdFromToken = (t: string): string =>
  decodeJwt(t)['urn:zitadel:iam:user:resourceowner:id'];

/**
 * Extract the logged-in browser user's OIDC access token from the saved
 * storageState, so API calls (e.g. folder create) are owned by that user and
 * remain visible in the UI. Requires the `setup` project to have run.
 */
export function getBrowserUserToken(authFile = AUTH_FILE): string {
  const state = JSON.parse(readFileSync(authFile, 'utf8'));
  for (const origin of state.origins ?? []) {
    for (const item of origin.localStorage ?? []) {
      if (typeof item?.name === 'string' && item.name.includes('oidc.user:')) {
        const parsed = JSON.parse(item.value);
        if (parsed?.access_token) return parsed.access_token as string;
      }
    }
  }
  throw new Error(`No oidc.user access_token found in ${authFile} — did the setup/login step run?`);
}
