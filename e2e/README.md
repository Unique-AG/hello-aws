# hello-aws e2e tests

Self-contained **browser + API** end-to-end tests for a Unique deployment on
AWS. No dependency on any private repo or package — **fork this repo, point it
at your own tenant, and run.**

## What's covered

| Surface | Tier | Flows |
| --- | --- | --- |
| Browser (Chromium) | `@watchdog` | OIDC login → simple chat → file upload/ingestion → create Space V2 |
| Browser (Chromium) | `@smoke` | broader per-area UI checks (KB, spaces, chat variants) |
| API (GraphQL) | `@watchdog` | service-user token → ingestion + chat critical path |
| API (GraphQL) | `@smoke` | scope-management, generate API token, broader API checks |

## Prerequisites on your tenant

1. A **dedicated testing organisation** (do not use a real customer org).
2. A **normal user** in that org for browser login (`TEST_USER` / `PASSWORD`).
3. A **Zitadel service account** (client-credentials) for API tests
   (`SERVICE_USER_CLIENT_ID` / `SERVICE_USER_CLIENT_SECRET`), plus the app
   **project id** (`ZITADEL_UNIQUE_APP_PROJECT_ID`).

## Run locally

```bash
cd e2e
npm ci
npx playwright install chromium
cp .env.example .env      # then fill in the blanks
npm run test:watchdog     # critical path (browser + api)
npm run test:smoke        # broader coverage
npm run test:browser      # only UI tests
npm run test:api          # only API tests
npm test                  # everything
npm run report            # open the last HTML report
```

Config is env-driven (see `config.ts`): set `BASE_DOMAIN` and the sibling hosts
(`api.<base>`, `id.<base>`) are derived automatically; override individual URLs
only if your DNS differs.

## Run in CI (your fork)

Two workflows under `.github/workflows/`, both gated behind the `e2e-aws`
GitHub Environment:

- `e2e-watchdog.yaml` — watchdog (browser + API), scheduled.
- `e2e-smoke.yaml` — smoke (browser + API), dispatch + weekday morning.

Provide **all** of these as **Environment secrets** on `e2e-aws` (nothing is a
plaintext variable): `BASE_DOMAIN`, `TEST_USER`, `ZITADEL_UNIQUE_APP_PROJECT_ID`,
`SERVICE_USER_CLIENT_ID`, `PASSWORD`, `SERVICE_USER_CLIENT_SECRET` (plus optional
`E2E_SLACK_WEBHOOK_URL`).

In the Unique-AG org these are managed as code in the private `infrastructure`
repo (GitHub Terraform provider) and stored as ciphertext — see that repo's
`providers/github/unique-ag`. Forkers set their own Environment secrets.

## Relationship to the internal QA suite

These flows are a self-contained reimplementation of the canonical Playwright
suite that Unique's QA team maintains internally for cross-tenant regression.
This copy is intentionally small and dependency-free so anyone running Unique on
AWS can validate their own deployment.
