#!/usr/bin/env bash
#######################################
# Setup the e2e test principals in Zitadel
#######################################
# The e2e suites need two principals that scripts/setup-zitadel.sh does not
# create: a human user for browser login and a service account for the API
# tests. Both must live in the customer organization, not the Cluster IAM org,
# or they cannot be granted the project.
#
# Writes the result straight into the `manual-e2e-aws-credentials` secret that
# .github/workflows/e2e-*.yaml read, so no credential is written to disk.
#
# Usage:
#   scripts/setup-e2e-user.sh <env> <pat> [--print]
#
# Arguments:
#   env     Environment name (e.g. sbx)
#   pat     Personal Access Token for a machine user with IAM_OWNER
#   --print Also print the JSON instead of only writing the secret
#
# Prerequisites:
#   - aws CLI with valid credentials (AWS_PROFILE set)
#   - curl, jq, yq
#   - scripts/setup-zitadel.sh already run (project, roles and org exist)
#
# Example:
#   AWS_PROFILE=sandbox scripts/setup-e2e-user.sh sbx wf7dDj...uUOEVBDaM5c
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
PAT="${2:-}"
PRINT="${3:-}"
[ -n "$ENV" ] && [ -n "$PAT" ] || error "Usage: $0 <env> <pat> [--print]"

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
# Zitadel rejects a password that fails the org policy, so keep the generated
# one long and mixed rather than base64 alone.
PASSWORD="E2e!$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 28)"

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
    "$(jq -n --arg p "$PASSWORD" '{newPassword:{password:$p,changeRequired:false}}')")
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
ROLE_KEYS=$(api GET "/management/v1/projects/${PROJECT_ID}/roles/_search" \
  | jq -c '[(.result // [])[].key]')
if [ "$ROLE_KEYS" = "[]" ] || [ -z "$ROLE_KEYS" ]; then
  warn "No project roles found; granting without roles"
  ROLE_KEYS='[]'
fi

for uid in "$HUMAN_ID" "$MACHINE_ID"; do
  GRANT=$(api POST "/management/v1/users/${uid}/grants" \
    "$(jq -n --arg p "$PROJECT_ID" --argjson r "$ROLE_KEYS" '{projectId:$p,roleKeys:$r}')")
  if echo "$GRANT" | jq -e '.code' >/dev/null 2>&1; then
    warn "Grant for ${uid}: $(echo "$GRANT" | jq -r '.message // .code')"
  else
    log "Granted project to ${uid}"
  fi
done

#######################################
# 4. Write the credentials the workflows read
#######################################
info "Writing ${SECRET_ID} in ${AWS_REGION} ..."
PAYLOAD=$(jq -n \
  --arg base "$DOMAIN_BASE" --arg proj "$PROJECT_ID" \
  --arg user "$E2E_USER" --arg pass "$PASSWORD" \
  --arg cid "$CLIENT_ID" --arg csec "$CLIENT_SECRET" \
  '{BASE_DOMAIN:$base,
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
