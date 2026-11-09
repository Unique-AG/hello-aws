#!/usr/bin/env bash
#######################################
# Setup the e2e test principals in Zitadel
#######################################
# Creates the two principals the e2e suites log in as, which setup-zitadel.sh
# does not: a human user for the browser flows and a service account for the API
# flows. Both are created in the customer org, the only org the project is
# granted to. The result is written to the `manual-e2e-aws-credentials` secret
# that .github/workflows/e2e-*.yaml read, so no credential reaches disk.
#
# Usage:
#   ZITADEL_PAT=... scripts/setup-e2e-user.sh <env> [--print]
#     env      Environment name (e.g. sbx)
#     --print  Also print the JSON, which otherwise only reaches the secret
#     PAT in the environment, not an argument: arguments are world-readable.
#
# Needs the aws CLI (AWS_PROFILE set), curl, jq, yq, and setup-zitadel.sh
# already run so the project, roles and grant exist.
#
# Example:
#   AWS_PROFILE=sandbox ZITADEL_PAT=wf7dDj... scripts/setup-e2e-user.sh sbx
#######################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()   { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1"; exit 1; }
info()  { echo -e "${BLUE}[i]${NC} $1"; }

ENV="${1:-}"
PRINT="${2:-}"
PAT="${ZITADEL_PAT:-}"
[ -n "$ENV" ] || error "Usage: ZITADEL_PAT=... $0 <env> [--print]"
[ -n "$PAT" ] || error "ZITADEL_PAT is not set (IAM_OWNER machine-user PAT)"

for cmd in aws curl jq yq; do
  command -v "$cmd" &>/dev/null || error "$cmd is required but not found"
done

# The per-environment file is the one the tooling reads; the copy at the root of
# 06-applications is not.
INSTANCE_CONFIG="${PROJECT_ROOT}/06-applications/${ENV}/instance-config.yaml"
[ -f "$INSTANCE_CONFIG" ] || error "No instance config at ${INSTANCE_CONFIG}"

DOMAIN_IDENTITY=$(yq -r '.domain.identity // ""' "$INSTANCE_CONFIG")
DOMAIN_BASE=$(yq -r '.domain.base // ""' "$INSTANCE_CONFIG")
AWS_REGION=$(yq -r '.aws.region // ""' "$INSTANCE_CONFIG")
PROJECT_ID=$(yq -r '.zitadel.projectId // ""' "$INSTANCE_CONFIG")
ORG_ID=$(yq -r '.zitadel.orgId // ""' "$INSTANCE_CONFIG")
for v in DOMAIN_IDENTITY DOMAIN_BASE AWS_REGION PROJECT_ID ORG_ID; do
  [ -n "${!v}" ] || error "${v} missing from ${INSTANCE_CONFIG}"
done

ZITADEL_HOST="https://${DOMAIN_IDENTITY}"
SECRET_ID="manual-e2e-aws-credentials"
E2E_USER="e2e@${DOMAIN_BASE}"

# Everything below rotates credentials that are only useful once stored, so
# prove the write target is reachable before touching Zitadel.
aws secretsmanager describe-secret --secret-id "$SECRET_ID" --region "$AWS_REGION" >/dev/null 2>&1 \
  || aws secretsmanager list-secrets --region "$AWS_REGION" --max-results 1 >/dev/null 2>&1 \
  || error "Cannot reach Secrets Manager in ${AWS_REGION}; check AWS_PROFILE"

info "Environment:  ${ENV}"
info "Zitadel host: ${ZITADEL_HOST}"
info "Organization: ${ORG_ID}"
info "Project:      ${PROJECT_ID}"

# Every call is scoped to the customer org: without the header the PAT's own
# org is used and the users land where the project cannot be granted.
api() {
  local method="$1" endpoint="$2" data="${3:-}"
  local args=(-s -X "$method" "${ZITADEL_HOST}${endpoint}"
    -H "Authorization: Bearer ${PAT}"
    -H "x-zitadel-orgid: ${ORG_ID}"
    -H "Content-Type: application/json")
  [ -n "$data" ] && args+=(-d "$data")
  curl "${args[@]}"
}

find_user() {
  api POST "/v2beta/users" \
    "{\"queries\":[{\"userNameQuery\":{\"userName\":\"$1\",\"method\":\"TEXT_QUERY_METHOD_EQUALS\"}}]}" \
    | jq -r '.result[0].userId // empty'
}

#######################################
# 1. Human user for browser login
#######################################
info "Creating human user ${E2E_USER} ..."
# A finite source, because `tr` reading /dev/urandom into `head` takes SIGPIPE and
# aborts under pipefail. LC_ALL=C belongs on `tr`: BSD tr reads the bytes as UTF-8
# and exits "Illegal byte sequence".
RANDOM_POOL=$(head -c 512 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9')
[ ${#RANDOM_POOL} -ge 28 ] || error "Could not generate a password"
# The fixed prefix only satisfies Zitadel's complexity policy; the entropy is
# all in the generated tail.
PASSWORD=$(printf '%s%s' 'E2e!' "${RANDOM_POOL:0:28}")

HUMAN_RESP=$(api POST "/management/v1/users/human/_import" "$(jq -n \
  --arg u "$E2E_USER" --arg p "$PASSWORD" \
  '{userName:$u,
    profile:{firstName:"E2E",lastName:"Test"},
    email:{email:$u,isEmailVerified:true},
    password:$p,
    passwordChangeRequired:false}')")
HUMAN_ID=$(echo "$HUMAN_RESP" | jq -r '.userId // empty')

if [ -z "$HUMAN_ID" ]; then
  warn "Import returned: $(echo "$HUMAN_RESP" | jq -c .)"
  HUMAN_ID=$(find_user "$E2E_USER")
  [ -n "$HUMAN_ID" ] || error "Could not create or find ${E2E_USER}"
  warn "Found existing user ${HUMAN_ID}; resetting its password"
  RESET=$(api POST "/management/v1/users/${HUMAN_ID}/password" \
    "$(jq -n --arg p "$PASSWORD" '{password:$p,noChangeRequired:true}')")
  echo "$RESET" | jq -e '.code' >/dev/null 2>&1 \
    && error "Password reset failed: $(echo "$RESET" | jq -c .)"
else
  log "Created human user ${HUMAN_ID}"
fi

#######################################
# 2. Service account for the API tests
#######################################
info "Creating machine user e2e-service ..."
MACHINE_RESP=$(api POST "/management/v1/users/machine" \
  '{"userName":"e2e-service","name":"E2E Service Account","description":"Client-credentials principal for the e2e API suite","accessTokenType":"ACCESS_TOKEN_TYPE_JWT"}')
MACHINE_ID=$(echo "$MACHINE_RESP" | jq -r '.userId // empty')
if [ -z "$MACHINE_ID" ]; then
  warn "Create returned: $(echo "$MACHINE_RESP" | jq -c .)"
  MACHINE_ID=$(find_user "e2e-service")
  [ -n "$MACHINE_ID" ] || error "Could not create or find e2e-service"
  warn "Found existing machine user ${MACHINE_ID}"
else
  log "Created machine user ${MACHINE_ID}"
fi

# Regenerating always returns a fresh secret; the previous one stops working,
# which is why the secret is rewritten in the same run.
info "Generating client credentials ..."
SECRET_RESP=$(api PUT "/management/v1/users/${MACHINE_ID}/secret" '{}')
CLIENT_ID=$(echo "$SECRET_RESP" | jq -r '.clientId // empty')
CLIENT_SECRET=$(echo "$SECRET_RESP" | jq -r '.clientSecret // empty')
[ -n "$CLIENT_ID" ] && [ -n "$CLIENT_SECRET" ] \
  || error "Failed to generate client credentials: $(echo "$SECRET_RESP" | jq -c .)"
log "Client credentials generated (clientId ${CLIENT_ID})"

#######################################
# 3. Grant the project to both principals
#######################################
# The project belongs to the Cluster IAM org. Seen from the customer org it is a
# granted project, which carries the grant id and the roles that grant allows.
GRANTED=$(api POST "/management/v1/granted_projects/_search" '{"query":{}}')
GRANT_ID=$(echo "$GRANTED" | jq -r --arg p "$PROJECT_ID" \
  'first((.result // [])[] | select(.projectId == $p) | .grantId) // empty')
ROLE_KEYS=$(echo "$GRANTED" | jq -c --arg p "$PROJECT_ID" \
  '[first((.result // [])[] | select(.projectId == $p)) // {} | (.grantedRoleKeys // [])[]]')
[ -n "$GRANT_ID" ] || error "Project ${PROJECT_ID} is not granted to org ${ORG_ID}; run setup-zitadel.sh first"
[ "$ROLE_KEYS" != "[]" ] || warn "The grant carries no roles; the test user will have none"
log "Project grant ${GRANT_ID} with $(echo "$ROLE_KEYS" | jq 'length') role(s)"

# Look the grant up rather than creating and reading the failure: the duplicate
# message is localised, so matching its text misses on a non-English instance.
for uid in "$HUMAN_ID" "$MACHINE_ID"; do
  FOUND=$(api POST "/management/v1/users/grants/_search" \
    "$(jq -n --arg u "$uid" '{queries:[{userIdQuery:{userId:$u}}]}')" \
    | jq -c --arg p "$PROJECT_ID" 'first((.result // [])[] | select(.projectId == $p)) // empty')

  if [ -z "$FOUND" ]; then
    GRANT=$(api POST "/management/v1/users/${uid}/grants" "$(jq -n \
      --arg p "$PROJECT_ID" --arg g "$GRANT_ID" --argjson r "$ROLE_KEYS" \
      '{projectId:$p,projectGrantId:$g,roleKeys:$r}')")
    echo "$GRANT" | jq -e '.code' >/dev/null 2>&1 \
      && error "Grant for ${uid} failed: $(echo "$GRANT" | jq -r '.message // .code')"
    log "Granted project to ${uid}"
    continue
  fi

  GRANT_UID=$(echo "$FOUND" | jq -r '.id')
  # sort the arrays, not their keys: -S orders object keys and would call an
  # identical role set a difference whenever the order came back shuffled.
  if [ "$(echo "$FOUND" | jq -c '(.roleKeys // []) | sort')" = "$(echo "$ROLE_KEYS" | jq -c 'sort')" ]; then
    log "Grant for ${uid} already carries the expected roles"
    continue
  fi
  UPD=$(api PUT "/management/v1/users/${uid}/grants/${GRANT_UID}" \
    "$(jq -n --argjson r "$ROLE_KEYS" '{roleKeys:$r}')")
  echo "$UPD" | jq -e '.code' >/dev/null 2>&1 \
    && error "Could not update grant for ${uid}: $(echo "$UPD" | jq -r '.message // .code')"
  log "Updated roles on the existing grant for ${uid}"
done

#######################################
# 4. Write the credentials the workflows read
#######################################
info "Writing ${SECRET_ID} in ${AWS_REGION} ..."
# Merge over what is already stored: every key becomes an environment variable,
# so extras such as SLACK_WEBHOOK_URL must survive a rotation.
EXISTING=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ID" \
  --region "$AWS_REGION" --query SecretString --output text 2>/dev/null || echo '{}')
echo "$EXISTING" | jq -e 'type == "object"' >/dev/null 2>&1 || EXISTING='{}'
PAYLOAD=$(jq -n --argjson old "$EXISTING" \
  --arg base "$DOMAIN_BASE" --arg proj "$PROJECT_ID" \
  --arg user "$E2E_USER" --arg pass "$PASSWORD" \
  --arg cid "$CLIENT_ID" --arg csec "$CLIENT_SECRET" \
  '$old + {BASE_DOMAIN:$base,
    ZITADEL_UNIQUE_APP_PROJECT_ID:$proj,
    TEST_USER:$user,
    PASSWORD:$pass,
    SERVICE_USER_CLIENT_ID:$cid,
    SERVICE_USER_CLIENT_SECRET:$csec}')

if aws secretsmanager describe-secret --secret-id "$SECRET_ID" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws secretsmanager put-secret-value --secret-id "$SECRET_ID" \
    --secret-string "$PAYLOAD" --region "$AWS_REGION" >/dev/null
  log "Rotated ${SECRET_ID}"
else
  aws secretsmanager create-secret --name "$SECRET_ID" \
    --secret-string "$PAYLOAD" --region "$AWS_REGION" >/dev/null
  log "Created ${SECRET_ID}"
fi

echo ""
log "Done."
info "TEST_USER:              ${E2E_USER}"
info "SERVICE_USER_CLIENT_ID: ${CLIENT_ID}"
info "PASSWORD / SERVICE_USER_CLIENT_SECRET: written to ${SECRET_ID}, not shown"
[ "$PRINT" = "--print" ] && { warn "Printing secret values (--print)"; echo "$PAYLOAD" | jq .; }
exit 0
