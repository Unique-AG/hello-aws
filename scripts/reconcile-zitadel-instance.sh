#!/usr/bin/env bash
#######################################
# Reconcile Zitadel instance configuration
#######################################
# Instance settings are not declarative: the chart's DefaultInstance and
# FirstInstance trees apply only when an instance is created, so a changed
# upstream default drifts silently and Argo CD still reports the app healthy.
# This compares the settings that matter against the instance and, with
# --apply, corrects them.
#
# Usage:
#   scripts/reconcile-zitadel-instance.sh <env> [--apply]
#     env      Environment name (e.g. sbx)
#     --apply  Write the desired state; without it, report and exit non-zero
#              on drift so CI can fail
#
# The PAT comes from the environment, not an argument: arguments are
# world-readable. It needs IAM_OWNER, which instance features require.
#
# Example:
#   AWS_PROFILE=sandbox ZITADEL_PAT=$(...) scripts/reconcile-zitadel-instance.sh sbx --apply
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
MODE="${2:-}"
PAT="${ZITADEL_PAT:-}"
[ -n "$ENV" ] || error "Usage: ZITADEL_PAT=... $0 <env> [--apply]"
[ -n "$PAT" ] || error "ZITADEL_PAT is not set (needs IAM_OWNER)"

for cmd in curl jq yq; do
  command -v "$cmd" &>/dev/null || error "$cmd is required but not found"
done

# The per-environment file is the one the tooling reads; the copy at the root of
# 06-applications is not.
INSTANCE_CONFIG="${PROJECT_ROOT}/06-applications/${ENV}/instance-config.yaml"
[ -f "$INSTANCE_CONFIG" ] || error "No instance config at ${INSTANCE_CONFIG}"

DOMAIN_IDENTITY=$(yq -r '.domain.identity // ""' "$INSTANCE_CONFIG")
[ -n "$DOMAIN_IDENTITY" ] || error "domain.identity missing from ${INSTANCE_CONFIG}"
ZITADEL_HOST="https://${DOMAIN_IDENTITY}"

# Bounded so a hung host fails the check rather than the job timeout, and
# non-zero on a transport error so a caller can tell that from an error body.
api() {
  local method="$1" endpoint="$2" data="${3:-}"
  local args=(-s --connect-timeout 10 --max-time 30 -X "$method" "${ZITADEL_HOST}${endpoint}"
    -H "Authorization: Bearer ${PAT}"
    -H "Content-Type: application/json")
  [ -n "$data" ] && args+=(-d "$data")
  curl "${args[@]}"
}

# A gateway can answer with HTML or nothing, which jq would read as absent
# rather than wrong — and absent would look like a passing check.
require_json() {
  echo "$1" | jq -e 'type == "object"' >/dev/null 2>&1 \
    || error "$2 was not a JSON object: $(echo "$1" | head -c 200)"
}

info "Environment:  ${ENV}"
info "Zitadel host: ${ZITADEL_HOST}"
if [ "$MODE" = "--apply" ]; then
  info "Mode: apply"
else
  info "Mode: check (pass --apply to correct drift)"
fi

DRIFT=0

#######################################
# Login V2 must not be required
#######################################
# This installation deploys the v2 login UI, so the instance should keep
# requiring it; a false here means authorize falls back to the legacy login.
FEATURES=$(api GET "/v2/features/instance") \
  || error "Could not reach ${ZITADEL_HOST} (connection or timeout)"
require_json "$FEATURES" "The instance features response"
if echo "$FEATURES" | jq -e '.code' >/dev/null 2>&1; then
  error "Could not read instance features: $(echo "$FEATURES" | jq -r '.message // .code')"
fi
echo "$FEATURES" | jq -e 'has("loginV2")' >/dev/null 2>&1 \
  || error "The instance features response has no loginV2 key; refusing to report on it"

LOGIN_V2=$(echo "$FEATURES" | jq -r '.loginV2.required // false')
if [ "$LOGIN_V2" != "true" ]; then
  DRIFT=1
  warn "loginV2.required is ${LOGIN_V2}; authorize is falling back to the legacy login"
  if [ "$MODE" = "--apply" ]; then
    RESP=$(api PUT "/v2/features/instance" '{"loginV2":{"required":true}}') \
      || error "Could not reach ${ZITADEL_HOST} while applying (connection or timeout)"
    require_json "$RESP" "The feature update response"
    if echo "$RESP" | jq -e '.code' >/dev/null 2>&1; then
      error "Could not set loginV2: $(echo "$RESP" | jq -r '.message // .code')"
    fi
    log "loginV2.required set to true"
    DRIFT=0
  fi
else
  log "loginV2.required is true"
fi

#######################################
# Result
#######################################
if [ "$DRIFT" -ne 0 ]; then
  error "Instance configuration has drifted. Re-run with --apply to correct it."
fi
log "Instance configuration matches."
