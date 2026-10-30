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
| API (GraphQL) | `@smoke @conduct` | Conduct: code runs in the sandbox, the workspace persists across turns, a generated file is stored |
| Browser (Chromium) | `@smoke @conduct` | Conduct: the answer renders a code-execution card |

## Prerequisites on your tenant

1. A **dedicated testing organisation** (do not use a real customer org).
2. A **normal user** in that org for browser login (`TEST_USER` / `PASSWORD`).
3. A **Zitadel service account** (client-credentials) for API tests
   (`SERVICE_USER_CLIENT_ID` / `SERVICE_USER_CLIENT_SECRET`), plus the app
   **project id** (`ZITADEL_UNIQUE_APP_PROJECT_ID`).
4. For the `@conduct` tests: Conduct enabled (assistants-core `sandboxConfig`, with
   the SandboxTemplate it names synced), and both users allowed to create spaces.
   The tests create Conduct spaces on the deployment's own Conduct defaults. The
   default Claude model must be one your LiteLLM serves; otherwise set
   `CONDUCT_MODEL`. A cold sandbox can take minutes, so each turn waits up to
   six.

## Run locally

```bash
cd e2e
npm ci
npx playwright install chromium
cp .env.example .env      # then fill in the blanks
npm run test:watchdog     # critical path (browser + api)
npm run test:smoke        # broader coverage
npm run test:conduct      # only the Conduct sandbox checks
npm run test:browser      # only UI tests
npm run test:api          # only API tests
npm test                  # everything
npm run report            # open the last HTML report
```

Config is env-driven (see `config.ts`): set `BASE_DOMAIN` and the sibling hosts
(`api.<base>`, `id.<base>`) are derived automatically; override individual URLs
only if your DNS differs.

## Run in CI (your fork)

Two workflows under `.github/workflows/`:

- `e2e-watchdog.yaml` — watchdog (browser + API), scheduled.
- `e2e-smoke.yaml` — smoke (browser + API), dispatch + weekday morning.

No tenant credentials live in this repo. Each job assumes the GitHub OIDC role
from `01-bootstrap` (`secrets.AWS_ROLE_ARN` — an ARN, not a credential) with no
static keys, then reads a single JSON secret from AWS Secrets Manager and masks
every value before exporting it.

The secret is `manual-e2e-aws-credentials` in the bootstrap account, hand-managed
and deliberately outside Terraform (same convention as
`manual-zitadel-scope-mgmt-pat`). Its JSON keys become environment variables, so
it must contain `BASE_DOMAIN`, `TEST_USER`, `ZITADEL_UNIQUE_APP_PROJECT_ID`,
`SERVICE_USER_CLIENT_ID`, `PASSWORD` and `SERVICE_USER_CLIENT_SECRET`. Any other
key is exported too — add `SLACK_WEBHOOK_URL` to enable the failure alert.

Create or rotate it from a populated `e2e/.env` with:

```bash
aws secretsmanager create-secret --region "$AWS_REGION" \
  --name manual-e2e-aws-credentials --secret-string file://creds.json
# later rotations: put-secret-value --secret-id manual-e2e-aws-credentials
```

A fork points `AWS_ROLE_ARN` at its own OIDC role, sets the `AWS_REGION` repository
variable when it deploys outside `eu-central-2`, and creates the same secret in
its own account. The role already carries `secretsmanager:*` via the bootstrap
deploy policy, so no extra IAM is needed.

## Relationship to the internal QA suite

These flows are a self-contained reimplementation of the canonical Playwright
suite that Unique's QA team maintains internally for cross-tenant regression.
This copy is intentionally small and dependency-free so anyone running Unique on
AWS can validate their own deployment.
