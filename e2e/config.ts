import 'dotenv/config';

/**
 * Central, env-driven configuration for the e2e suite.
 *
 * Everything is derived from a single BASE_DOMAIN so a fork only has to set its
 * own domain + credentials. Individual URLs can still be overridden explicitly
 * (useful for split/non-standard DNS) via the matching *_URL / *_DOMAIN vars.
 *
 * See .env.example for the full list and how to obtain each value.
 */

function required(name: string): string {
  const v = process.env[name];
  if (!v || v.trim() === '') {
    throw new Error(
      `Missing required env var ${name}. Copy .env.example to .env (local) ` +
        `or set it as a CI secret/variable. See e2e/README.md.`,
    );
  }
  return v;
}

function optional(name: string, fallback: string): string {
  const v = process.env[name];
  return v && v.trim() !== '' ? v : fallback;
}

// Base domain of the deployment, e.g. "your-tenant.example.com".
// Sibling hosts default to api.<base> and id.<base> (the hello-aws domain
// scheme: domain.{base,api,identity}); override if your DNS differs.
const BASE_DOMAIN = required('BASE_DOMAIN');
const API_DOMAIN = optional('API_DOMAIN', `api.${BASE_DOMAIN}`);
const IDENTITY_DOMAIN = optional('IDENTITY_DOMAIN', `id.${BASE_DOMAIN}`);

const APP = `https://${BASE_DOMAIN}`;
const API = `https://${API_DOMAIN}`;

export const config = {
  // Free-form label for reports/logs; not load-bearing.
  testEnv: optional('TEST_ENV', 'AWS'),

  // The dedicated testing organisation/tenant slug the tests operate in.
  testOrganisation: required('TEST_ORGANISATION'),

  // ── App (browser) URLs ──────────────────────────────────────────────
  baseURL: optional('CHAT_APP_URL', `${APP}/chat`),
  chatAppURL: optional('CHAT_APP_URL', `${APP}/chat`),
  knowledgeUploadAppURL: optional('KNOWLEDGE_UPLOAD_APP_URL', `${APP}/knowledge-upload`),
  adminAppURL: optional('ADMIN_APP_URL', `${APP}/admin`),

  // ── Gateway (API) URLs ──────────────────────────────────────────────
  // NOTE: paths are explicit (not the monorepo's uat1/us1 "legacy vs gen2"
  // heuristic) — AWS uses the /chat + /ingestion form, verified live.
  scopeManagementApiURL: optional('SCOPE_MANAGEMENT_BACKEND_API_URL', `${API}/scope-management/graphql`),
  chatApiURL: optional('CHAT_BACKEND_API_URL', `${API}/chat/graphql`),
  ingestionApiURL: optional('INGESTION_BACKEND_API_URL', `${API}/ingestion/graphql`),
  appsApiURL: optional('APPS_BACKEND_API_URL', `${API}/apps/graphql`),
  publicSdkURL: optional('PUBLIC_SDK_URL', `${API}/public/chat`),

  // ── Identity (Zitadel / OIDC) ───────────────────────────────────────
  zitadelDomain: optional('ZITADEL_DOMAIN', `https://${IDENTITY_DOMAIN}`),
  zitadelProjectId: required('ZITADEL_UNIQUE_APP_PROJECT_ID'),

  // ── Browser test user (interactive OIDC login) ──────────────────────
  user: {
    username: required('TEST_USER'),
    password: required('PASSWORD'),
  },

  // ── API service user (client-credentials → bearer token) ────────────
  serviceUser: {
    clientId: required('SERVICE_USER_CLIENT_ID'),
    clientSecret: required('SERVICE_USER_CLIENT_SECRET'),
  },
} as const;

export type AppConfig = typeof config;
