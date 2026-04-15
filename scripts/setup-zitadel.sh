#!/usr/bin/env bash
#######################################
# Setup Zitadel — full environment bootstrap
#######################################
# Run once after Zitadel deploys. Uses a machine user PAT (with IAM_OWNER)
# to perform the complete Zitadel setup:
#
#   1. Create customer organization
#   2. Create "unique" project in Cluster IAM org
#   3. Create "unique-app" OIDC application (PKCE)
#   4. Configure token settings (JWT, roles in token)
#   5. Create all project roles
#   6. Grant project to customer organization
#   7. Create scope-management service user + PAT → AWS Secrets Manager
#   8. Add Zitadel Actions (addGrant)
#   9. Delete provision user (self-destruct)
#
# Usage:
#   scripts/setup-zitadel.sh <env> <pat> [org-name]
#
# Arguments:
#   env       Environment name (e.g., dev, test, prod)
#   pat       Personal Access Token for a machine user with IAM_OWNER
#   org-name  Customer organization name (default: "Unique")
#
# Prerequisites:
#   - aws CLI with valid credentials (AWS_PROFILE set)
#   - curl, jq
#   - Zitadel deployed with a machine user that has IAM_OWNER
#
# Domain pattern: <env>.aws.unique.dev
#   Identity: id.<env>.aws.unique.dev
#   App:      <env>.aws.unique.dev
#   API:      api.<env>.aws.unique.dev
#
# Examples:
#   AWS_PROFILE=sandbox scripts/setup-zitadel.sh sbx wf7dDj...uUOEVBDaM5c
#   AWS_PROFILE=sandbox scripts/setup-zitadel.sh sbx wf7dDj...uUOEVBDaM5c "Acme Corp"
#######################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()   { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1"; exit 1; }
info()  { echo -e "${BLUE}[i]${NC} $1"; }

# Parse arguments
ENV="${1:-}"
PAT="${2:-}"
ORG_NAME="${3:-Unique}"
ADMIN_EMAIL="${4:-}"
if [ -z "$ENV" ] || [ -z "$PAT" ]; then
  error "Usage: $0 <env> <pat> [org-name] [admin-email]"
fi

# Check prerequisites
for cmd in aws curl jq; do
  if ! command -v "$cmd" &>/dev/null; then
    error "$cmd is required but not found"
  fi
done

#######################################
# Configuration
#######################################
ZITADEL_HOST="https://id.${ENV}.aws.unique.dev"
BASE_URL="https://${ENV}.aws.unique.dev"
AWS_SM_SECRET="manual-zitadel-scope-mgmt-pat"
PROJECT_NAME="unique"
APP_NAME="unique-app"

# Read AWS region
AWS_REGION=$(aws configure get region 2>/dev/null || echo "eu-central-2")

info "Environment: ${ENV}"
info "Zitadel host: ${ZITADEL_HOST}"
info "Base URL: ${BASE_URL}"
info "Organization: ${ORG_NAME}"
info "AWS region: ${AWS_REGION}"

#######################################
# Helper: call Zitadel API
#######################################
api() {
  local method="$1" endpoint="$2" data="${3:-}"
  local args=(-s -X "$method" "${ZITADEL_HOST}${endpoint}"
    -H "Authorization: Bearer ${PAT}"
    -H "Content-Type: application/json")
  [ -n "$data" ] && args+=(-d "$data")
  curl "${args[@]}"
}

api_check() {
  local resp="$1" label="$2"
  if echo "$resp" | jq -e '.code' >/dev/null 2>&1; then
    local code msg
    code=$(echo "$resp" | jq -r '.code')
    msg=$(echo "$resp" | jq -r '.message')
    if [ "$code" = "6" ]; then
      warn "${label}: already exists"
      return 1
    else
      warn "${label}: code=${code} msg=${msg}"
      return 1
    fi
  fi
  return 0
}

#######################################
# 1. Wait for Zitadel API
#######################################
log "PAT provided (${#PAT} chars)"
info "Waiting for Zitadel API at ${ZITADEL_HOST}..."
ATTEMPTS=0
MAX_ATTEMPTS=60
while [ "$ATTEMPTS" -lt "$MAX_ATTEMPTS" ]; do
  HTTP=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
    "${ZITADEL_HOST}/debug/healthz" 2>/dev/null || echo "000")
  [ "$HTTP" = "200" ] && break
  ATTEMPTS=$((ATTEMPTS + 1))
  sleep 5
done
[ "$HTTP" = "200" ] || error "Zitadel not healthy after $((MAX_ATTEMPTS * 5))s"
log "Zitadel is healthy"

#######################################
# 2. Create customer organization
#######################################
info "Creating organization '${ORG_NAME}'..."
ORG_RESP=$(api POST "/v2/organizations" \
  "{\"name\":\"${ORG_NAME}\"}")

ORG_ID=$(echo "$ORG_RESP" | jq -r '.organizationId // empty')
if [ -z "$ORG_ID" ]; then
  if echo "$ORG_RESP" | jq -r '.message' 2>/dev/null | grep -qi "already\|taken"; then
    warn "Organization already exists, searching..."
    ORG_LIST=$(api POST "/admin/v1/orgs/_search" \
      "{\"queries\":[{\"nameQuery\":{\"name\":\"${ORG_NAME}\",\"method\":\"TEXT_QUERY_METHOD_EQUALS\"}}]}")
    ORG_ID=$(echo "$ORG_LIST" | jq -r '.result[0].id // empty')
    [ -n "$ORG_ID" ] || error "Failed to find organization '${ORG_NAME}'"
    warn "Found existing organization: ${ORG_ID}"
  else
    error "Failed to create organization: $(echo "$ORG_RESP" | jq -c .)"
  fi
else
  log "Created organization '${ORG_NAME}': ${ORG_ID}"
fi

# Get the Cluster IAM (root) org ID
ROOT_ORG_RESP=$(api GET "/admin/v1/orgs/default")
ROOT_ORG_ID=$(echo "$ROOT_ORG_RESP" | jq -r '.org.id // empty')
if [ -z "$ROOT_ORG_ID" ]; then
  # Fallback: search for Cluster IAM
  ROOT_ORG_LIST=$(api POST "/admin/v1/orgs/_search" \
    '{"queries":[{"nameQuery":{"name":"Cluster IAM","method":"TEXT_QUERY_METHOD_EQUALS"}}]}')
  ROOT_ORG_ID=$(echo "$ROOT_ORG_LIST" | jq -r '.result[0].id // empty')
fi
[ -n "$ROOT_ORG_ID" ] || error "Could not find root organization (Cluster IAM)"
log "Root organization (Cluster IAM): ${ROOT_ORG_ID}"

#######################################
# 3. Create project in Cluster IAM org
#######################################
info "Creating project '${PROJECT_NAME}' in Cluster IAM..."
PROJECT_RESP=$(api POST "/management/v1/projects" \
  "{\"name\":\"${PROJECT_NAME}\",\"projectRoleAssertion\":true,\"projectRoleCheck\":true,\"hasProjectCheck\":true}" )

PROJECT_ID=$(echo "$PROJECT_RESP" | jq -r '.id // empty')
if [ -z "$PROJECT_ID" ]; then
  warn "Create project returned: $(echo "$PROJECT_RESP" | jq -c .)"
  # Search for existing project
  PROJECT_LIST=$(api POST "/management/v1/projects/_search" \
    "{\"queries\":[{\"nameQuery\":{\"name\":\"${PROJECT_NAME}\",\"method\":\"TEXT_QUERY_METHOD_EQUALS\"}}]}")
  PROJECT_ID=$(echo "$PROJECT_LIST" | jq -r '.result[0].id // empty')
  [ -n "$PROJECT_ID" ] || error "Failed to create or find project '${PROJECT_NAME}'"
  warn "Found existing project: ${PROJECT_ID}"
else
  log "Created project '${PROJECT_NAME}': ${PROJECT_ID}"
fi

# Update project settings (role assertion, role check, has project check)
info "Updating project settings..."
api PUT "/management/v1/projects/${PROJECT_ID}" \
  "{\"name\":\"${PROJECT_NAME}\",\"projectRoleAssertion\":true,\"projectRoleCheck\":true,\"hasProjectCheck\":true}" >/dev/null
log "Project settings updated (roleAssertion=true, roleCheck=true, hasProjectCheck=true)"

#######################################
# 4. Create OIDC application (PKCE)
#######################################
info "Creating OIDC application '${APP_NAME}'..."
APP_RESP=$(api POST "/management/v1/projects/${PROJECT_ID}/apps/oidc" \
  "{
    \"name\": \"${APP_NAME}\",
    \"redirectUris\": [
      \"${BASE_URL}/chat\",
      \"${BASE_URL}/chat/\",
      \"${BASE_URL}/chat/api/auth/callback/zitadel\",
      \"${BASE_URL}/knowledge-upload\",
      \"${BASE_URL}/knowledge-upload/\",
      \"${BASE_URL}/knowledge-upload/api/auth/callback/zitadel\",
      \"${BASE_URL}/admin\",
      \"${BASE_URL}/admin/\",
      \"${BASE_URL}/admin/api/auth/callback/zitadel\",
      \"${BASE_URL}/theme\",
      \"${BASE_URL}/theme/\"
    ],
    \"postLogoutRedirectUris\": [
      \"${BASE_URL}/chat\",
      \"${BASE_URL}/knowledge-upload\",
      \"${BASE_URL}/theme\",
      \"${BASE_URL}/admin\"
    ],
    \"responseTypes\": [\"OIDC_RESPONSE_TYPE_CODE\"],
    \"grantTypes\": [\"OIDC_GRANT_TYPE_AUTHORIZATION_CODE\"],
    \"appType\": \"OIDC_APP_TYPE_WEB\",
    \"authMethodType\": \"OIDC_AUTH_METHOD_TYPE_NONE\",
    \"accessTokenType\": \"OIDC_TOKEN_TYPE_JWT\",
    \"accessTokenRoleAssertion\": true,
    \"idTokenRoleAssertion\": true,
    \"idTokenUserinfoAssertion\": true
  }")

APP_ID=$(echo "$APP_RESP" | jq -r '.appId // empty')
CLIENT_ID=$(echo "$APP_RESP" | jq -r '.clientId // empty')
if [ -z "$APP_ID" ]; then
  warn "Create app returned: $(echo "$APP_RESP" | jq -c .)"
  # Search for existing app
  APP_LIST=$(api POST "/management/v1/projects/${PROJECT_ID}/apps/_search" \
    "{\"queries\":[{\"nameQuery\":{\"name\":\"${APP_NAME}\",\"method\":\"TEXT_QUERY_METHOD_EQUALS\"}}]}")
  APP_ID=$(echo "$APP_LIST" | jq -r '(.result // [])[0].id // empty')
  CLIENT_ID=$(echo "$APP_LIST" | jq -r '(.result // [])[0].oidcConfig.clientId // empty')
  [ -n "$APP_ID" ] || error "Failed to create or find application '${APP_NAME}'"
  warn "Found existing application: ${APP_ID}"

  # Update OIDC config to ensure redirect URIs are correct
  info "Updating OIDC application config..."
  api PUT "/management/v1/projects/${PROJECT_ID}/apps/${APP_ID}/oidc_config" \
    "{
      \"redirectUris\": [
        \"${BASE_URL}/chat\",
        \"${BASE_URL}/chat/\",
        \"${BASE_URL}/chat/api/auth/callback/zitadel\",
        \"${BASE_URL}/knowledge-upload\",
        \"${BASE_URL}/knowledge-upload/\",
        \"${BASE_URL}/knowledge-upload/api/auth/callback/zitadel\",
        \"${BASE_URL}/admin\",
        \"${BASE_URL}/admin/\",
        \"${BASE_URL}/admin/api/auth/callback/zitadel\",
        \"${BASE_URL}/theme\",
        \"${BASE_URL}/theme/\"
      ],
      \"postLogoutRedirectUris\": [
        \"${BASE_URL}/chat\",
        \"${BASE_URL}/knowledge-upload\",
        \"${BASE_URL}/theme\",
        \"${BASE_URL}/admin\"
      ],
      \"responseTypes\": [\"OIDC_RESPONSE_TYPE_CODE\"],
      \"grantTypes\": [\"OIDC_GRANT_TYPE_AUTHORIZATION_CODE\"],
      \"authMethodType\": \"OIDC_AUTH_METHOD_TYPE_NONE\",
      \"accessTokenType\": \"OIDC_TOKEN_TYPE_JWT\",
      \"accessTokenRoleAssertion\": true,
      \"idTokenRoleAssertion\": true,
      \"idTokenUserinfoAssertion\": true
    }" >/dev/null
  log "OIDC application config updated"
else
  log "Created application '${APP_NAME}': ${APP_ID} (clientId: ${CLIENT_ID})"
fi

#######################################
# 5. Create project roles
#######################################
info "Creating project roles (upsert)..."
ROLE_DEFS=(
  "chat.chat.basic|Chat Basic|chat"
  "chat.knowledge.read|Knowledge Read|knowledge-base"
  "chat.knowledge.write|Knowledge Write|knowledge-base"
  "chat.data.admin|Data Admin|admin"
  "chat.feedback.read|Feedback Read|admin"
  "chat.admin.all|Admin All|admin"
  "chat.debug.read|Debug Read|admin"
  "admin.user-management.write|User Management Write|admin"
  "admin.space.write|Space Write|admin"
  "admin.app-repository.write|App Repository Write|admin"
  "connector.admin.read|Connector Admin Read|admin"
  "connector.admin.write|Connector Admin Write|admin"
)

ROLE_KEYS='[]'
for def in "${ROLE_DEFS[@]}"; do
  IFS='|' read -r rkey rname rgroup <<< "$def"
  ROLE_KEYS=$(echo "$ROLE_KEYS" | jq --arg k "$rkey" '. + [$k]')
  ROLE_RESP=$(api POST "/management/v1/projects/${PROJECT_ID}/roles" \
    "{\"roleKey\":\"${rkey}\",\"displayName\":\"${rname}\",\"group\":\"${rgroup}\"}")
  if echo "$ROLE_RESP" | jq -e '.code' >/dev/null 2>&1; then
    code=$(echo "$ROLE_RESP" | jq -r '.code')
    if [ "$code" = "6" ]; then
      info "  ${rkey} (exists)"
    else
      warn "  ${rkey}: $(echo "$ROLE_RESP" | jq -r '.message')"
    fi
  else
    info "  ${rkey} (created)"
  fi
done
log "Project roles upserted (${#ROLE_DEFS[@]} roles)"

#######################################
# 6. Grant project to customer organization
#######################################
info "Granting project to organization '${ORG_NAME}'..."
GRANT_RESP=$(api POST "/management/v1/projects/${PROJECT_ID}/grants" \
  "{\"grantedOrgId\":\"${ORG_ID}\",\"roleKeys\":${ROLE_KEYS}}")

GRANT_ID=$(echo "$GRANT_RESP" | jq -r '.grantId // empty')
if [ -z "$GRANT_ID" ]; then
  warn "Grant returned: $(echo "$GRANT_RESP" | jq -c .)"
  # Search for existing grant
  GRANT_LIST=$(api POST "/management/v1/projects/${PROJECT_ID}/grants/_search" '{}')
  GRANT_ID=$(echo "$GRANT_LIST" | jq -r "[(.result // [])[] | select(.grantedOrgId==\"${ORG_ID}\")] | .[0].grantId // empty")
  if [ -n "$GRANT_ID" ]; then
    warn "Found existing grant: ${GRANT_ID}"
    # Update grant to include all roles
    info "Updating grant with all roles..."
    api PUT "/management/v1/projects/${PROJECT_ID}/grants/${GRANT_ID}" \
      "{\"roleKeys\":${ROLE_KEYS}}" >/dev/null
    log "Grant updated with all roles"
  fi
else
  log "Granted project to '${ORG_NAME}': ${GRANT_ID}"
fi

#######################################
# 7. Create scope-management service user
#######################################
info "Creating scope-management machine user..."
CREATE_USER_RESP=$(api POST "/management/v1/users/machine" \
  '{"userName":"scope-management","name":"Scope Management Service Account","description":"Automated Zitadel configuration","accessTokenType":"ACCESS_TOKEN_TYPE_JWT"}')

SM_USER_ID=$(echo "$CREATE_USER_RESP" | jq -r '.userId // empty')
if [ -z "$SM_USER_ID" ]; then
  warn "Create returned: $(echo "$CREATE_USER_RESP" | jq -c .)"
  SEARCH_RESP=$(api POST "/v2beta/users" \
    '{"queries":[{"userNameQuery":{"userName":"scope-management","method":"TEXT_QUERY_METHOD_EQUALS"}}]}')
  SM_USER_ID=$(echo "$SEARCH_RESP" | jq -r '.result[0].userId // empty')
  [ -n "$SM_USER_ID" ] || error "Failed to create or find scope-management user"
  warn "Found existing scope-management user: ${SM_USER_ID}"
else
  log "Created scope-management user: ${SM_USER_ID}"
fi

# Assign instance-level roles
info "Assigning instance roles to scope-management..."
api POST "/admin/v1/members" \
  "{\"userId\":\"${SM_USER_ID}\",\"roles\":[\"IAM_OWNER_VIEWER\"]}" >/dev/null 2>&1
api PUT "/admin/v1/members/${SM_USER_ID}" \
  '{"roles":["IAM_OWNER_VIEWER","IAM_USER_MANAGER"]}' >/dev/null 2>&1
log "Assigned IAM_OWNER_VIEWER + IAM_USER_MANAGER"

# Generate PAT
info "Generating PAT for scope-management..."
PAT_RESP=$(api POST "/management/v1/users/${SM_USER_ID}/pats" \
  '{"expirationDate":"2029-01-01T00:00:00Z"}')

SCOPE_PAT=$(echo "$PAT_RESP" | jq -r '.token // empty')
if [ -z "$SCOPE_PAT" ]; then
  error "Failed to generate PAT: $(echo "$PAT_RESP" | jq -c .)"
fi
log "PAT generated (${#SCOPE_PAT} chars)"

# Write to AWS Secrets Manager
info "Writing PAT to AWS Secrets Manager (${AWS_SM_SECRET})..."
aws secretsmanager put-secret-value \
  --secret-id "$AWS_SM_SECRET" \
  --secret-string "$SCOPE_PAT" \
  --region "$AWS_REGION" >/dev/null
log "PAT written to AWS SM"

#######################################
# 8. Add Zitadel Actions
#######################################
info "Creating Zitadel action: addGrant..."

# The addGrant action needs the project grant ID
if [ -n "$GRANT_ID" ]; then
  ADDGRANT_CODE="function addGrant(ctx, api) { api.userGrants.push({ projectID: '${PROJECT_ID}', projectGrantID: '${GRANT_ID}', roles: ['chat.chat.basic'] }); }"

  ACTION_RESP=$(api POST "/management/v1/actions" \
    "{\"name\":\"addGrant\",\"script\":\"${ADDGRANT_CODE}\",\"timeout\":\"10s\",\"allowedToFail\":true}")

  ACTION_ID=$(echo "$ACTION_RESP" | jq -r '.id // empty')
  if [ -z "$ACTION_ID" ]; then
    warn "Action create returned: $(echo "$ACTION_RESP" | jq -c .)"
    # Search for existing action
    ACTION_LIST=$(api POST "/management/v1/actions/_search" '{}')
    ACTION_ID=$(echo "$ACTION_LIST" | jq -r '[(.result // [])[] | select(.name=="addGrant")] | .[0].id // empty')
    if [ -n "$ACTION_ID" ]; then
      warn "Found existing addGrant action: ${ACTION_ID}, updating..."
      api PUT "/management/v1/actions/${ACTION_ID}" \
        "{\"name\":\"addGrant\",\"script\":\"${ADDGRANT_CODE}\",\"timeout\":\"10s\",\"allowedToFail\":true}" >/dev/null
    fi
  else
    log "Created addGrant action: ${ACTION_ID}"
  fi

  # Assign to Post Creation trigger
  if [ -n "$ACTION_ID" ]; then
    info "Assigning addGrant to Post Creation triggers (Internal + External Auth)..."
    api POST "/management/v1/flows/3/trigger/3" \
      "{\"actionIds\":[\"${ACTION_ID}\"]}" >/dev/null 2>&1
    log "addGrant assigned to Internal Authentication → Post Creation (flow 3, trigger 3)"
    api POST "/management/v1/flows/1/trigger/3" \
      "{\"actionIds\":[\"${ACTION_ID}\"]}" >/dev/null 2>&1
    log "addGrant assigned to External Authentication → Post Creation (flow 1, trigger 3)"
  fi
else
  warn "No grant ID available, skipping addGrant action"
fi

#######################################
# 9. Delete provision user
#######################################
info "Looking up provision user..."
PROV_SEARCH=$(api POST "/v2beta/users" \
  '{"queries":[{"userNameQuery":{"userName":"provision","method":"TEXT_QUERY_METHOD_EQUALS"}}]}')
PROV_USER_ID=$(echo "$PROV_SEARCH" | jq -r '.result[0].userId // empty')

if [ -n "$PROV_USER_ID" ]; then
  info "Deactivating provision (${PROV_USER_ID})..."
  api POST "/management/v1/users/${PROV_USER_ID}/_deactivate" '{}' >/dev/null
  info "Deleting provision..."
  api DELETE "/management/v1/users/${PROV_USER_ID}" >/dev/null
  log "provision user deleted"
else
  warn "Could not find provision user to delete (may already be deleted)"
fi

#######################################
# Summary
#######################################
echo ""
log "=== Zitadel setup complete ==="
echo ""
info "Organization:    ${ORG_NAME} (${ORG_ID})"
info "Root Org:        Cluster IAM (${ROOT_ORG_ID})"
info "Project:         ${PROJECT_NAME} (${PROJECT_ID})"
info "Application:     ${APP_NAME} (${APP_ID})"
info "Client ID:       ${CLIENT_ID}"
info "Grant ID:        ${GRANT_ID:-N/A}"
info "Scope Mgmt User: ${SM_USER_ID}"
info "PAT Secret:      ${AWS_SM_SECRET}"
echo ""
#######################################
# 10. Create admin user (optional)
#######################################
if [ -n "$ADMIN_EMAIL" ]; then
  # Extract name parts from email (first.last@domain → First Last)
  LOCAL_PART="${ADMIN_EMAIL%%@*}"
  FIRST_NAME=$(echo "$LOCAL_PART" | cut -d. -f1 | sed 's/./\U&/')
  LAST_NAME=$(echo "$LOCAL_PART" | cut -d. -f2- | sed 's/./\U&/')
  [ -z "$LAST_NAME" ] && LAST_NAME="Admin"
  ADMIN_PASSWORD="$(openssl rand -base64 16 | tr -d '/+=' | head -c 16)!"

  info "Creating admin user ${ADMIN_EMAIL} in org ${ORG_NAME}..."

  # Create human user in customer org
  ADMIN_RESP=$(curl -s -X POST "${ZITADEL_HOST}/management/v1/users/human/_import" \
    -H "Authorization: Bearer ${PAT}" \
    -H "x-zitadel-orgid: ${ORG_ID}" \
    -H "Content-Type: application/json" \
    -d "{\"userName\":\"${ADMIN_EMAIL}\",\"profile\":{\"firstName\":\"${FIRST_NAME}\",\"lastName\":\"${LAST_NAME}\",\"displayName\":\"${FIRST_NAME} ${LAST_NAME}\",\"preferredLanguage\":\"en\"},\"email\":{\"email\":\"${ADMIN_EMAIL}\",\"isEmailVerified\":true},\"password\":\"${ADMIN_PASSWORD}\",\"passwordChangeRequired\":false}")

  ADMIN_USER_ID=$(echo "$ADMIN_RESP" | jq -r '.userId // empty')
  if [ -z "$ADMIN_USER_ID" ]; then
    warn "Could not create admin user: $(echo "$ADMIN_RESP" | jq -r '.message // empty')"
  else
    log "Created admin user: ${ADMIN_USER_ID}"

    # Grant all project roles from root org
    ALL_ROLES='["chat.chat.basic","chat.knowledge.read","chat.knowledge.write","chat.data.admin","chat.feedback.read","chat.admin.all","chat.debug.read","admin.user-management.write","admin.space.write","admin.app-repository.write","connector.admin.read","connector.admin.write"]'
    curl -s -X POST "${ZITADEL_HOST}/management/v1/users/${ADMIN_USER_ID}/grants" \
      -H "Authorization: Bearer ${PAT}" \
      -H "x-zitadel-orgid: ${ROOT_ORG_ID}" \
      -H "Content-Type: application/json" \
      -d "{\"projectId\":\"${PROJECT_ID}\",\"roleKeys\":${ALL_ROLES}}" >/dev/null
    log "Granted all project roles"

    # Add IAM_OWNER instance role
    curl -s -X POST "${ZITADEL_HOST}/admin/v1/members" \
      -H "Authorization: Bearer ${PAT}" \
      -H "Content-Type: application/json" \
      -d "{\"userId\":\"${ADMIN_USER_ID}\",\"roles\":[\"IAM_OWNER\"]}" >/dev/null
    log "Granted IAM_OWNER"

    # Add ORG_OWNER on customer org
    curl -s -X POST "${ZITADEL_HOST}/management/v1/orgs/me/members" \
      -H "Authorization: Bearer ${PAT}" \
      -H "x-zitadel-orgid: ${ORG_ID}" \
      -H "Content-Type: application/json" \
      -d "{\"userId\":\"${ADMIN_USER_ID}\",\"roles\":[\"ORG_OWNER\"]}" >/dev/null
    log "Granted ORG_OWNER"

    echo ""
    log "Admin user created:"
    info "  Email:    ${ADMIN_EMAIL}"
    info "  Password: ${ADMIN_PASSWORD}"
    info "  User ID:  ${ADMIN_USER_ID}"
  fi
fi

#######################################
# 11. Patch instance-config.yaml
#######################################
INSTANCE_CONFIG="${PROJECT_ROOT}/06-applications/${ENV}/instance-config.yaml"
if [ -f "$INSTANCE_CONFIG" ] && command -v yq &>/dev/null; then
  info "Patching ${INSTANCE_CONFIG} with new Zitadel IDs..."
  yq -i ".zitadel.projectId = \"${PROJECT_ID}\"" "$INSTANCE_CONFIG"
  yq -i ".zitadel.clientId = \"${CLIENT_ID}\"" "$INSTANCE_CONFIG"
  yq -i ".zitadel.orgId = \"${ORG_ID}\"" "$INSTANCE_CONFIG"
  log "instance-config.yaml updated"
  info "Run: cd 06-applications && ./scripts/configure-instance.sh ${ENV}"
else
  warn "Could not patch instance-config.yaml (file not found or yq missing)"
  info "Update manually:"
  info "  ZITADEL_CLIENT_ID:    ${CLIENT_ID}"
  info "  ZITADEL_ORG_ID:       ${ORG_ID}"
  info "  ZITADEL_PROJECT_ID:   ${PROJECT_ID}"
fi
echo ""
