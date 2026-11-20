#!/usr/bin/env bash
#######################################
# Reconcile LiteLLM virtual keys
#######################################
# Every caller holding the master key can mint keys, read spend and change
# proxy settings. Each caller gets its own virtual key instead, scoped to the
# inference routes. The key material is a seeded secret, so this registers it
# with LiteLLM and keeps its scope correct rather than inventing a key.
#
# Usage:
#   scripts/reconcile-litellm-keys.sh <env> [--apply]
#     env      Environment name (e.g. sbx)
#     --apply  Write the desired state; without it, report and exit non-zero
#              on drift
#
# LiteLLM has no ingress, so this port-forwards to the service: it needs a
# kubectl context for the cluster as well as AWS credentials.
#
# Example:
#   AWS_PROFILE=sandbox scripts/reconcile-litellm-keys.sh sbx --apply
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
[ -n "$ENV" ] || error "Usage: $0 <env> [--apply]"
APPLY=false
[ "$MODE" = "--apply" ] && APPLY=true

for cmd in kubectl jq aws terraform curl; do
  command -v "$cmd" &>/dev/null || error "$cmd is required but not found"
done

TERRAFORM_DIR="${PROJECT_ROOT}/04-data-and-ai/terraform"
[ -d "$TERRAFORM_DIR" ] || error "Terraform directory not found: $TERRAFORM_DIR"
NAMESPACE="${LITELLM_NAMESPACE:-unique}"

# The callers that must stop sending the master key. openai_routes is LiteLLM's
# inference surface; it excludes key management, spend and UI routes.
CALLERS="chat ingestion ingestion_worker"
ALLOWED_ROUTES='["openai_routes"]'

#######################################
# Terraform outputs
#######################################
info "Reading Terraform outputs from ${TERRAFORM_DIR} ..."
TF=$(cd "$TERRAFORM_DIR" && terraform output -json 2>/dev/null) \
  || error "Could not read Terraform outputs. Run terraform init in ${TERRAFORM_DIR} first."
tf() { echo "$TF" | jq -r "$1"; }
AWS_REGION=$(tf '.aws_region.value')
SECRET_ARNS=$(tf '.secret_arns.value')
[ "$AWS_REGION" != "null" ] || error "Terraform outputs do not look like the data layer's."

# Values are read into variables and never echoed; nothing secret is passed on
# a command line, which is world-readable.
secret_value() {         # ref -- prints the value, empty when unset
  local arn v
  arn=$(echo "$SECRET_ARNS" | jq -r --arg k "$1" '.[$k] // empty')
  [ -n "$arn" ] || return 1
  v=$(aws secretsmanager get-secret-value --secret-id "$arn" --region "$AWS_REGION" \
        --query SecretString --output text 2>/dev/null) || return 1
  [ "$v" != "None" ] || return 1
  printf '%s' "$v"
}

MASTER_KEY=$(secret_value litellm_proxy_master_key) \
  || error "The LiteLLM master key has no value; run seed-secrets.sh first."

#######################################
# Reach the proxy
#######################################
PORT="${LITELLM_LOCAL_PORT:-14000}"
KCTL=(kubectl)
[ -n "${KUBECTL_CONTEXT:-}" ] && KCTL+=(--context "${KUBECTL_CONTEXT}")
"${KCTL[@]}" -n "$NAMESPACE" port-forward svc/litellm "${PORT}:4000" >/dev/null 2>&1 &
PF_PID=$!
trap 'kill "$PF_PID" 2>/dev/null || true' EXIT
BASE="http://127.0.0.1:${PORT}"

# Any HTTP answer means the forward is up; 401 is an answer. curl prints 000
# itself when it cannot connect, so a fallback 000 would make this always true.
CODE=000
for _ in $(seq 1 30); do
  CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "${BASE}/health/liveliness" 2>/dev/null || true)
  if [ -n "$CODE" ] && [ "$CODE" != "000" ]; then break; fi
  kill -0 "$PF_PID" 2>/dev/null || error "kubectl port-forward exited — is the context pointing at ${ENV}?"
  sleep 1
done
[ "$CODE" != "000" ] || error "LiteLLM did not answer on ${BASE} — is the kubectl context pointing at ${ENV}?"

# Failures return empty rather than non-zero: under set -e a failing curl here
# ends the run with curl's exit code and no explanation.
api() {                  # method path [json-body]
  local method="$1" path="$2" body="${3:-}"
  if [ -n "$body" ]; then
    curl -s --max-time 30 -X "$method" "${BASE}${path}" \
      -H "Authorization: Bearer ${MASTER_KEY}" -H 'content-type: application/json' -d "$body" || true
  else
    curl -s --max-time 30 -X "$method" "${BASE}${path}" \
      -H "Authorization: Bearer ${MASTER_KEY}" || true
  fi
}

info "Environment: ${ENV}   namespace: ${NAMESPACE}   mode: $([ "$APPLY" = true ] && echo apply || echo report)"

# Prove the master key works before touching anything, so a stale key reads as
# itself rather than as every caller being unregistered.
PROBE=$(api GET "/key/list?size=1&return_full_object=true")
echo "$PROBE" | jq -e '.keys' >/dev/null 2>&1 \
  || error "Could not list keys (is the master key current?): $(echo "$PROBE" | head -c 200)"

#######################################
# Reconcile
#######################################
DRIFT=0
for c in $CALLERS; do
  alias="hello-aws-${c//_/-}"
  ref="litellm_virtual_key_${c}"

  if ! key=$(secret_value "$ref"); then
    warn "${alias}: ${ref} has no value — run seed-secrets.sh first"
    DRIFT=1; continue
  fi

  # Asking for the one alias rather than paging the whole list, which caps at 100.
  # keys[] holds either an alias string or the whole object, so take objects only.
  found=$(api GET "/key/list?size=100&return_full_object=true&key_alias=${alias}")
  if ! echo "$found" | jq -e '.keys' >/dev/null 2>&1; then
    warn "${alias}: could not be looked up ($(echo "$found" | head -c 160))"
    DRIFT=1; continue
  fi
  existing=$(echo "$found" | jq -c --arg a "$alias" \
    'first(.keys[]? | select(type == "object") | select((.key_alias // "") == $a)) // empty')

  if [ -z "$existing" ]; then
    if [ "$APPLY" = false ]; then
      warn "${alias}: not registered with LiteLLM"; DRIFT=1; continue
    fi
    body=$(jq -n --arg k "$key" --arg a "$alias" --argjson r "$ALLOWED_ROUTES" \
      '{key:$k, key_alias:$a, allowed_routes:$r}')
    out=$(api POST "/key/generate" "$body")
    echo "$out" | jq -e '.key' >/dev/null 2>&1 \
      || { warn "${alias}: could not create ($(echo "$out" | head -c 160))"; DRIFT=1; continue; }
    log "${alias}: registered, routes ${ALLOWED_ROUTES}"
    continue
  fi

  have=$(echo "$existing" | jq -c '(.allowed_routes // []) | sort')
  want=$(echo "$ALLOWED_ROUTES" | jq -c 'sort')
  if [ "$have" = "$want" ]; then
    info "${alias}: scope already correct"
    continue
  fi

  if [ "$APPLY" = false ]; then
    warn "${alias}: routes are ${have}, should be ${want}"; DRIFT=1; continue
  fi
  body=$(jq -n --arg k "$key" --argjson r "$ALLOWED_ROUTES" '{key:$k, allowed_routes:$r}')
  out=$(api POST "/key/update" "$body")
  echo "$out" | jq -e '.key // .token' >/dev/null 2>&1 \
    || { warn "${alias}: could not update ($(echo "$out" | head -c 160))"; DRIFT=1; continue; }
  log "${alias}: scope corrected to ${want}"
done

unset MASTER_KEY

if [ "$DRIFT" -ne 0 ] && [ "$APPLY" = false ]; then
  warn "Virtual keys are not in the desired state. Re-run with --apply to correct."
  exit 1
fi
[ "$DRIFT" -eq 0 ] && log "Virtual keys match the desired state."
exit 0
