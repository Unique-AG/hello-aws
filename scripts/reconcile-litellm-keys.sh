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
# Empty means every model the proxy serves: no caller loses one it uses today.
ALLOWED_MODELS='[]'

sha256() {               # reads stdin
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'
  else shasum -a 256 | awk '{print $1}'; fi
}

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

# Values are read into variables and never echoed, and never reach an argument.
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
KCTL=(kubectl)
[ -n "${KUBECTL_CONTEXT:-}" ] && KCTL+=(--context "${KUBECTL_CONTEXT}")

PF_LOG=$(mktemp); chmod 600 "$PF_LOG"
trap 'kill "${PF_PID:-}" 2>/dev/null || true; rm -f "$PF_LOG"' EXIT

# An empty local port lets the kernel pick a free one. Taking a fixed port and
# probing it proves nothing: another process answering it would be sent the key.
"${KCTL[@]}" -n "$NAMESPACE" port-forward svc/litellm "${LITELLM_LOCAL_PORT:-}:4000" \
  >"$PF_LOG" 2>&1 &
PF_PID=$!

# Only kubectl's own bind line proves this process owns the listener.
PORT=""
for _ in $(seq 1 30); do
  PORT=$(sed -nE 's#^Forwarding from 127\.0\.0\.1:([0-9]+) .*#\1#p' "$PF_LOG" | head -1)
  [ -n "$PORT" ] && break
  kill -0 "$PF_PID" 2>/dev/null \
    || { cat "$PF_LOG" >&2; error "kubectl port-forward exited before binding — is the context pointing at ${ENV}?"; }
  sleep 1
done
[ -n "$PORT" ] || { cat "$PF_LOG" >&2; error "kubectl port-forward never reported a local port."; }
BASE="http://127.0.0.1:${PORT}"

# --noproxy: curl sends loopback through http_proxy when one is set, which would
# put the key on an external plaintext hop. Failures return empty, not non-zero:
# under set -e a failing curl ends the run with no explanation.
api() {                  # method path [json-body]
  local method="$1" path="$2" body="${3:-}" args=() tmp=""
  if [ -n "$body" ]; then
    tmp=$(mktemp); chmod 600 "$tmp"; printf '%s' "$body" >"$tmp"
    args+=(-H 'content-type: application/json' --data "@${tmp}")
  fi
  # The bearer arrives on stdin and the body from a 0600 file: an argument is
  # world-readable through /proc on a shared host.
  printf 'header = "Authorization: Bearer %s"\n' "$MASTER_KEY" \
    | curl -s --noproxy '*' --max-time 30 -X "$method" "${BASE}${path}" \
        ${args[@]+"${args[@]}"} -K - || true
  [ -n "$tmp" ] && rm -f "$tmp"
  return 0
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
# Asking for the one alias rather than paging the whole list, which caps at 100.
# keys[] holds either an alias string or the whole object, so take objects only.
lookup() {               # alias -- the registration as JSON, empty when absent
  local alias="$1" found
  found=$(api GET "/key/list?size=100&return_full_object=true&key_alias=${alias}")
  echo "$found" | jq -e '.keys' >/dev/null 2>&1 || return 1
  echo "$found" | jq -c --arg a "$alias" \
    'first(.keys[]? | select(type == "object") | select((.key_alias // "") == $a)) // empty'
}

scope_of() { jq -c '{routes: ((.allowed_routes // []) | sort), models: ((.models // []) | sort)}'; }
WANT_SCOPE=$(ROUTES="$ALLOWED_ROUTES" MODELS="$ALLOWED_MODELS" jq -n -c \
  '{routes: (env.ROUTES | fromjson | sort), models: (env.MODELS | fromjson | sort)}')

desired_body() {         # alias key -- the registration this script wants
  KEY="$2" ALIAS="$1" ROUTES="$ALLOWED_ROUTES" MODELS="$ALLOWED_MODELS" jq -n \
    '{key: env.KEY, key_alias: env.ALIAS,
      allowed_routes: (env.ROUTES | fromjson), models: (env.MODELS | fromjson)}'
}

# LiteLLM stores the sha256 of the key, so this says whether the registration
# under this alias is the seeded key with the scope this script owns.
settled() {              # alias key
  local alias="$1" key="$2" got
  got=$(lookup "$alias") || return 1
  [ -n "$got" ] || return 1
  [ "$(echo "$got" | jq -r '.token // ""')" = "$(printf '%s' "$key" | sha256)" ] || return 1
  [ "$(echo "$got" | scope_of)" = "$WANT_SCOPE" ] || return 1
  return 0
}

# generate upserts by token: when the seeded key is already registered under a
# different alias it returns .key and changes nothing, so read the state back.
register() {             # alias key -- creates or corrects, then verifies
  local alias="$1" key="$2" out
  out=$(api POST "/key/generate" "$(desired_body "$alias" "$key")")
  settled "$alias" "$key" && return 0
  # Held under another alias: move it rather than leave the key under two names.
  api POST "/key/update" "$(desired_body "$alias" "$key")" >/dev/null
  settled "$alias" "$key" && return 0
  printf '%s' "$(echo "$out" | head -c 160)"
  return 1
}

DRIFT=0
for c in $CALLERS; do
  alias="hello-aws-${c//_/-}"
  ref="litellm_virtual_key_${c}"

  if ! key=$(secret_value "$ref"); then
    warn "${alias}: ${ref} has no value — run seed-secrets.sh first"
    DRIFT=1; continue
  fi

  if ! existing=$(lookup "$alias"); then
    warn "${alias}: could not be looked up (is the master key current?)"
    DRIFT=1; continue
  fi

  if [ -z "$existing" ]; then
    if [ "$APPLY" = false ]; then
      warn "${alias}: not registered with LiteLLM"; DRIFT=1; continue
    fi
    if ! msg=$(register "$alias" "$key"); then
      warn "${alias}: could not create (${msg})"; DRIFT=1; continue
    fi
    log "${alias}: registered, routes ${ALLOWED_ROUTES}"
    continue
  fi

  # After a rotation the alias still resolves to the pre-rotation key, so the
  # sha256 is what says the registration is still the seeded one.
  have_token=$(echo "$existing" | jq -r '.token // ""')
  want_token=$(printf '%s' "$key" | sha256)
  if [ "$have_token" != "$want_token" ]; then
    if [ "$APPLY" = false ]; then
      warn "${alias}: registered key is not the seeded one (rotated?)"; DRIFT=1; continue
    fi
    api POST "/key/delete" "$(ALIAS="$alias" jq -n '{key_aliases: [env.ALIAS]}')" >/dev/null
    if ! msg=$(register "$alias" "$key"); then
      warn "${alias}: could not re-register after rotation (${msg})"; DRIFT=1; continue
    fi
    log "${alias}: re-registered with the seeded key"
    continue
  fi

  have=$(echo "$existing" | scope_of)
  if [ "$have" = "$WANT_SCOPE" ]; then
    info "${alias}: scope already correct"
    continue
  fi

  if [ "$APPLY" = false ]; then
    warn "${alias}: scope is ${have}, should be ${WANT_SCOPE}"; DRIFT=1; continue
  fi
  # Read back rather than trust the response: an update that changed nothing
  # still answers with the key.
  api POST "/key/update" "$(desired_body "$alias" "$key")" >/dev/null
  if ! settled "$alias" "$key"; then
    warn "${alias}: update did not take effect"; DRIFT=1; continue
  fi
  log "${alias}: scope corrected to ${WANT_SCOPE}"
done

unset MASTER_KEY

# Non-zero on any unresolved drift, in either mode: automation that applies and
# still has failures must not read as success.
if [ "$DRIFT" -ne 0 ]; then
  if [ "$APPLY" = false ]; then
    warn "Virtual keys are not in the desired state. Re-run with --apply to correct."
  else
    warn "Some virtual keys could not be brought to the desired state."
  fi
  exit 1
fi
log "Virtual keys match the desired state."
exit 0
