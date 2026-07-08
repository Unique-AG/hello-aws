import { config } from '../config';
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
