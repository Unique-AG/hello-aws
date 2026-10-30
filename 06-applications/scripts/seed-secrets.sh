#!/usr/bin/env bash
#######################################
# Seed Secrets — give every secret a value after terraform apply
#######################################
#
# Terraform creates the secrets and fills in the ones it knows (endpoints,
# ports, bucket names). It cannot write credentials, because they would land in
# state. This script writes the rest.
#
# What it seeds is declared in secrets.yaml, not in the control flow below, so
# the inventory can be read and reviewed on its own. External values are
# fetched at run time from the store named in <env>/secrets-sources.yaml, which
# is not committed; nothing secret is written to disk or passed on a command
# line.
#
# Usage:
#   ./scripts/seed-secrets.sh <env>            seed whatever is still empty
#   ./scripts/seed-secrets.sh <env> --check    report only, write nothing
#   ./scripts/seed-secrets.sh <env> --force    rewrite values that already exist
#   ./scripts/seed-secrets.sh <env> --only X   act on one secret
#
# --check exits non-zero when a required secret has no value, so it can be run
# after a deploy to find out whether this step was ever done.
#######################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_ROOT="$(cd "${APPS_DIR}/.." && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()   { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1" >&2; exit 1; }
info()  { echo -e "${BLUE}[i]${NC} $1"; }

ENV=""; CHECK=false; FORCE=false; ONLY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK=true; shift ;;
    --force) FORCE=true; shift ;;
    --only)  ONLY="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    -*) error "Unknown option: $1" ;;
    *) ENV="$1"; shift ;;
  esac
done
[[ -n "$ENV" ]] || error "Usage: $0 <env> [--check] [--force] [--only <name>]"

MANIFEST="${APPS_DIR}/secrets.yaml"
SOURCES="${APPS_DIR}/${ENV}/secrets-sources.yaml"
TERRAFORM_DIR="${PROJECT_ROOT}/04-data-and-ai/terraform"

#######################################
# Prerequisites
#######################################
MISSING=()
for cmd in aws jq yq openssl python3; do
  command -v "$cmd" &>/dev/null || MISSING+=("$cmd")
done
(( ${#MISSING[@]} == 0 )) || error "Required tool(s) not found: ${MISSING[*]}"
[[ -f "$MANIFEST" ]] || error "Inventory not found: $MANIFEST"
[[ -d "$TERRAFORM_DIR" ]] || error "Terraform directory not found: $TERRAFORM_DIR"

#######################################
# Terraform outputs
#######################################
info "Reading Terraform outputs from ${TERRAFORM_DIR} ..."
TF=$(cd "$TERRAFORM_DIR" && terraform output -json 2>/dev/null) \
  || error "Could not read Terraform outputs. Run terraform init in ${TERRAFORM_DIR} first."

tf() { echo "$TF" | jq -r "$1"; }
AWS_REGION=$(tf '.aws_region.value')
SECRET_ARNS=$(tf '.secret_arns.value')
CONN_ARNS=$(tf '.psql_connection_string_secret_arns.value')
PG_DATABASES=$(tf '.postgresql_databases.value')
AURORA_ENDPOINT=$(tf '.aurora_cluster_endpoint.value')
AURORA_PW_ARN=$(tf '.aurora_master_password_secret_arn.value')
S3_IAM_USER=$(tf '.s3_access_iam_user_name.value')
[[ "$AWS_REGION" != "null" ]] || error "Terraform outputs do not look like the data layer's."
info "Region: ${AWS_REGION}   Env: ${ENV}   Mode: $( $CHECK && echo check || { $FORCE && echo force || echo seed; } )"

#######################################
# Inventory
#######################################
# Secrets the derived steps write, resolved up front so check mode can see them.
ENDPOINT_ARN=$(echo "$SECRET_ARNS" | jq -r '.azure_openai_endpoint_definitions // empty')
S3_KEY_ARN=$(echo "$SECRET_ARNS" | jq -r '.s3_access_key_id // empty')
S3_SECRET_ARN=$(echo "$SECRET_ARNS" | jq -r '.s3_secret_access_key // empty')

# A derived entry stands for several secrets; --only matches its manifest name.
wanted() { [[ -z "$ONLY" || "$ONLY" == "$1" ]]; }

entries() { yq -o=json '.secrets' "$MANIFEST" | jq -c '.[]'; }
field()   { echo "$1" | jq -r "$2 // empty"; }

# Resolve a manifest entry to the Secrets Manager id it writes to.
target_id() {
  local e="$1" ref id
  ref=$(field "$e" '.ref'); id=$(field "$e" '.id')
  if [[ -n "$id" ]]; then echo "$id"; return; fi
  if [[ -n "$ref" ]]; then echo "$SECRET_ARNS" | jq -r --arg k "$ref" '.[$k] // empty'; return; fi
  echo ""
}

# A secret counts as populated when it has a current version.
has_value() {
  local sid="$1" v
  v=$(aws secretsmanager describe-secret --secret-id "$sid" --region "$AWS_REGION" \
        --query 'length(VersionIdsToStages)' --output text 2>/dev/null) || return 1
  [[ -n "$v" && "$v" != "None" && "$v" != "0" ]]
}

# Write without putting the value on a command line.
put_value() {
  local sid="$1"
  aws secretsmanager put-secret-value --secret-id "$sid" \
    --secret-string "file:///dev/stdin" --region "$AWS_REGION" >/dev/null
}

gen_password() { openssl rand -base64 48 | tr -d '/+=' | head -c 32; }
gen_hex()      { openssl rand -hex 32; }
# Zitadel needs a symbol; gen_password is alphanumeric so DSNs need no escaping.
gen_complex()  { printf '%sAa1!' "$(openssl rand -base64 48 | tr -d '/+=' | head -c 28)"; }

#######################################
# External sources
#######################################
SOURCES_PRESENT=false
[[ -f "$SOURCES" ]] && SOURCES_PRESENT=true

# Reads one external secret as JSON. The reference syntax is the credential
# store's own; only 1Password's op:// is understood here, and anything else is
# treated as a literal value so a fork can point this at something different.
resolve_ref() {
  local ref="$1"
  [[ -n "$ref" && "$ref" != "null" ]] || return 1
  if [[ "$ref" == op://* ]]; then
    command -v op &>/dev/null || return 1
    op read "$ref" 2>/dev/null || return 1
  else
    printf '%s' "$ref"
  fi
}

# A source is either one reference, or a map of field name to reference, which
# is assembled into a JSON object because that is the shape those secrets take.
read_external() {
  local key="$1" kind ref out k v
  $SOURCES_PRESENT || return 1
  kind=$(yq -r ".sources.${key} | type" "$SOURCES" 2>/dev/null) || return 1
  case "$kind" in
    "!!str")
      resolve_ref "$(yq -r ".sources.${key}" "$SOURCES")" || return 1
      ;;
    "!!map")
      out="{}"
      for k in $(yq -r ".sources.${key} | keys | .[]" "$SOURCES" 2>/dev/null); do
        v=$(resolve_ref "$(yq -r ".sources.${key}.${k}" "$SOURCES")") || return 1
        out=$(jq -c --arg k "$k" --arg v "$v" '. + {($k): $v}' <<<"$out")
        unset v
      done
      [[ "$out" != "{}" ]] || return 1
      printf '%s' "$out"
      ;;
    *) return 1 ;;
  esac
}

#######################################
# Plan — resolve every entry before writing anything
#######################################
PLAN=()        # name|kind|id|state      state: empty | populated | unresolved
PROBLEMS=()

while read -r e; do
  [[ -n "$e" ]] || continue
  name=$(field "$e" '.name'); kind=$(field "$e" '.kind')
  optional=$(field "$e" '.optional')
  [[ -n "$ONLY" && "$ONLY" != "$name" ]] && continue

  # Deriers that fan out to several secrets report themselves.
  # Derived entries are reported by expansion below, not as one opaque row.
  if [[ "$kind" == "derive" ]]; then
    continue
  fi

  # Optional entries and ones another step owns must not be reported as faults.
  tier=required
  [[ "$optional" == "true" ]] && tier=optional
  [[ "$kind" == "managed" ]] && tier=managed

  sid=$(target_id "$e")
  if [[ -z "$sid" ]]; then
    PROBLEMS+=("${name}: no Secrets Manager id — neither .id nor a known .ref")
    PLAN+=("${name}|${kind}|-|unresolved|${tier}")
    continue
  fi

  if has_value "$sid"; then state=populated; else state=empty; fi
  PLAN+=("${name}|${kind}|${sid}|${state}|${tier}")

  # An external value we cannot fetch is a problem now, not halfway through.
  if [[ "$kind" == "external" && ( "$state" == "empty" || "$FORCE" == "true" ) ]]; then
    src=$(field "$e" '.source')
    if ! read_external "$src" >/dev/null 2>&1; then
      if [[ "$optional" == "true" ]]; then
        warn "${name}: no source configured (optional) — will be left empty"
      else
        PROBLEMS+=("${name}: cannot read from source '${src}'. Add it to ${ENV}/secrets-sources.yaml")
      fi
    fi
  fi
done < <(entries)

#######################################
# Check mode — report and exit
#######################################
if $CHECK; then
  echo ""
  printf "%-42s %-9s %s\n" "SECRET" "KIND" "STATE"
  printf "%-42s %-9s %s\n" "------" "----" "-----"
  missing=0
  for row in "${PLAN[@]}"; do
    IFS='|' read -r n k s st tier <<< "$row"
    shown="$st"
    [[ "$tier" != "required" && "$st" == "empty" ]] && shown="empty (${tier})"
    printf "%-42s %-9s %s\n" "$n" "$k" "$shown"
    if [[ "$tier" == "required" && ( "$st" == "empty" || "$st" == "unresolved" ) ]]; then
      missing=$((missing+1))
    fi
  done
  # The derived rows above stand in for real secrets; report those.
  report_one() {
    local label="$1" arn="$2" st
    if [[ -n "$arn" ]] && has_value "$arn"; then st=populated; else st=empty; missing=$((missing+1)); fi
    printf "%-42s %-9s %s\n" "$label" "derive" "$st"
  }
  if wanted psql-connection-strings; then
    for db in $(echo "$PG_DATABASES" | jq -r 'keys[]'); do
      report_one "psql-connection-string-${db}" "$(echo "$CONN_ARNS" | jq -r --arg k "$db" '.[$k] // empty')"
    done
  fi
  wanted azure-openai-endpoint-definitions && report_one "azure-openai-endpoint-definitions" "$ENDPOINT_ARN"
  if wanted s3-access-key; then
    report_one "s3-access-key-id"     "$S3_KEY_ARN"
    report_one "s3-secret-access-key" "$S3_SECRET_ARN"
  fi
  echo ""
  if (( missing > 0 )); then
    error "${missing} secret(s) have no value. Run without --check to seed them."
  fi
  log "Every secret in the inventory has a value."
  exit 0
fi

#######################################
# Stop before writing if anything is unresolvable
#######################################
if (( ${#PROBLEMS[@]} > 0 )); then
  echo ""
  warn "Cannot proceed — nothing has been written:"
  for p in "${PROBLEMS[@]}"; do echo "    - $p"; done
  echo ""
  error "Fix the above and run again."
fi

#######################################
# Seed
#######################################
SEEDED=0; SKIPPED=0; LEFT_EMPTY=0
LITELLM_MASTER_KEY=""

seed_one() {
  local name="$1" sid="$2" state="$3" kind="$4" e="$5"
  if [[ "$state" == "populated" && "$FORCE" == "false" ]]; then
    info "${name}: already set"; SKIPPED=$((SKIPPED+1)); return 0
  fi

  local value=""
  case "$kind" in
    generate)
      case "$(field "$e" '.generator')" in
        hex)     value=$(gen_hex) ;;
        complex) value=$(gen_complex) ;;
        *)       value=$(gen_password) ;;
      esac
      ;;
    external)
      local src; src=$(field "$e" '.source')
      if ! value=$(read_external "$src"); then
        warn "${name}: no source configured — left empty"; LEFT_EMPTY=$((LEFT_EMPTY+1)); return 0
      fi
      ;;
    managed)
      info "${name}: owned by $(field "$e" '.owner') — not touched"; return 0
      ;;
  esac

  printf '%s' "$value" | put_value "$sid"
  unset value
  log "${name}: seeded"
  SEEDED=$((SEEDED+1))
}

while read -r e; do
  [[ -n "$e" ]] || continue
  name=$(field "$e" '.name'); kind=$(field "$e" '.kind')
  [[ -n "$ONLY" && "$ONLY" != "$name" ]] && continue
  [[ "$kind" == "derive" ]] && continue

  sid=$(target_id "$e")
  if has_value "$sid"; then state=populated; else state=empty; fi
  seed_one "$name" "$sid" "$state" "$kind" "$e"

  # Keep the litellm key in hand; the endpoint definitions embed it.
  if [[ "$name" == "litellm-proxy-master-key" ]]; then
    LITELLM_MASTER_KEY=$(aws secretsmanager get-secret-value --secret-id "$sid" \
      --region "$AWS_REGION" --query SecretString --output text 2>/dev/null || echo "")
  fi
done < <(entries)

#######################################
# Derived: PostgreSQL connection strings
#######################################
if wanted psql-connection-strings; then
info "Connection strings ..."
AURORA_PASSWORD=$(aws secretsmanager get-secret-value --secret-id "$AURORA_PW_ARN" \
  --region "$AWS_REGION" --query SecretString --output text 2>/dev/null || echo "")
if [[ -z "$AURORA_PASSWORD" || "$AURORA_PASSWORD" == "None" ]]; then
  error "The Aurora master password secret has no value; the connection strings cannot be built."
fi
AURORA_USERNAME=$(aws secretsmanager get-secret-value \
  --secret-id "$(echo "$SECRET_ARNS" | jq -r '.psql_username')" \
  --region "$AWS_REGION" --query SecretString --output text 2>/dev/null || echo "dbadmin")
AURORA_PORT=$(aws secretsmanager get-secret-value \
  --secret-id "$(echo "$SECRET_ARNS" | jq -r '.psql_port')" \
  --region "$AWS_REGION" --query SecretString --output text 2>/dev/null || echo "5432")

for db in $(echo "$PG_DATABASES" | jq -r 'keys[]'); do
  arn=$(echo "$CONN_ARNS" | jq -r --arg k "$db" '.[$k] // empty')
  [[ -n "$arn" ]] || { warn "psql-connection-string-${db}: no ARN in outputs"; continue; }
  if has_value "$arn" && [[ "$FORCE" == "false" ]]; then
    info "psql-connection-string-${db}: already set"; SKIPPED=$((SKIPPED+1)); continue
  fi
  dbname=$(echo "$PG_DATABASES" | jq -r --arg k "$db" '.[$k].name')
  enc=$(AURORA_PASSWORD="$AURORA_PASSWORD" python3 -c \
    'import os;from urllib.parse import quote;print(quote(os.environ["AURORA_PASSWORD"],safe=""))')
  printf 'postgresql://%s:%s@%s:%s/%s' "$AURORA_USERNAME" "$enc" "$AURORA_ENDPOINT" "$AURORA_PORT" "$dbname" \
    | put_value "$arn"
  unset enc
  log "psql-connection-string-${db}: seeded"
  SEEDED=$((SEEDED+1))
done
unset AURORA_PASSWORD
fi

#######################################
# Derived: LiteLLM endpoint definitions
#######################################
# The model names come from the litellm overlay, so this cannot drift from what
# the proxy actually serves.
if wanted azure-openai-endpoint-definitions; then
LITELLM_OVERLAY="${APPS_DIR}/${ENV}/value-overlays/litellm/litellm.yaml"
# --only skips the loop that would have kept the key, so read it back here.
if [[ -z "$LITELLM_MASTER_KEY" ]]; then
  LITELLM_SID=$(target_id "$(entries | jq -c 'select(.name=="litellm-proxy-master-key")')")
  [[ -n "$LITELLM_SID" ]] && LITELLM_MASTER_KEY=$(aws secretsmanager get-secret-value \
    --secret-id "$LITELLM_SID" --region "$AWS_REGION" --query SecretString --output text 2>/dev/null || echo "")
  unset LITELLM_SID
fi
if [[ -n "$LITELLM_MASTER_KEY" && -f "$LITELLM_OVERLAY" ]]; then
  if has_value "$ENDPOINT_ARN" && [[ "$FORCE" == "false" ]]; then
    info "azure-openai-endpoint-definitions: already set"; SKIPPED=$((SKIPPED+1))
  else
    MODELS=$(yq -o=json '[.proxy_config.model_list[].model_name]' "$LITELLM_OVERLAY" 2>/dev/null || echo '[]')
    if [[ "$(echo "$MODELS" | jq 'length')" -eq 0 ]]; then
      warn "azure-openai-endpoint-definitions: no models found in $(basename "$LITELLM_OVERLAY") — left empty"
      LEFT_EMPTY=$((LEFT_EMPTY+1))
    else
      jq -n --arg key "$LITELLM_MASTER_KEY" --arg region "$AWS_REGION" --argjson models "$MODELS" \
        '[{endpoint:"http://litellm.unique.svc:4000", key:$key, location:$region,
           models: ($models | map({modelName:., deploymentName:., modelVersion:"1.0"}))}]' \
        | put_value "$ENDPOINT_ARN"
      log "azure-openai-endpoint-definitions: seeded ($(echo "$MODELS" | jq 'length') models)"
      SEEDED=$((SEEDED+1))
    fi
  fi
else
  warn "azure-openai-endpoint-definitions: needs the litellm master key and ${LITELLM_OVERLAY#$PROJECT_ROOT/} — left empty"
  LEFT_EMPTY=$((LEFT_EMPTY+1))
fi
fi
unset LITELLM_MASTER_KEY

#######################################
# Derived: S3 IAM access key
#######################################
# Creating a key invalidates the one in use, so this only runs when the secret
# is empty, or when a rotation was asked for explicitly.
if ! wanted s3-access-key; then
  :
elif has_value "$S3_KEY_ARN" && has_value "$S3_SECRET_ARN" && [[ "$FORCE" == "false" ]]; then
  info "s3-access-key: already set"; SKIPPED=$((SKIPPED+1))
else
  $FORCE && warn "Rotating the S3 access key — the current one stops working."
  for old in $(aws iam list-access-keys --user-name "$S3_IAM_USER" \
                 --query 'AccessKeyMetadata[].AccessKeyId' --output text 2>/dev/null || true); do
    aws iam delete-access-key --user-name "$S3_IAM_USER" --access-key-id "$old"
    warn "Deleted previous access key ${old}"
  done
  KEY_JSON=$(aws iam create-access-key --user-name "$S3_IAM_USER" --output json)
  echo "$KEY_JSON" | jq -r '.AccessKey.AccessKeyId'     | tr -d '\n' | put_value "$S3_KEY_ARN"
  echo "$KEY_JSON" | jq -r '.AccessKey.SecretAccessKey' | tr -d '\n' | put_value "$S3_SECRET_ARN"
  unset KEY_JSON
  log "s3-access-key: seeded"
  SEEDED=$((SEEDED+2))
fi

#######################################
# Verify — the point of the exercise
#######################################
# Seeding is not done because the script reached the end. It is done when every
# secret in the inventory actually has a value.
echo ""
info "Verifying ..."
STILL_EMPTY=()

while read -r e; do
  [[ -n "$e" ]] || continue
  name=$(field "$e" '.name'); kind=$(field "$e" '.kind')
  [[ "$kind" == "derive" || "$kind" == "managed" ]] && continue
  [[ "$(field "$e" '.optional')" == "true" ]] && continue
  [[ -n "$ONLY" && "$ONLY" != "$name" ]] && continue
  sid=$(target_id "$e")
  [[ -n "$sid" ]] && has_value "$sid" || STILL_EMPTY+=("$name")
done < <(entries)

# Scoped the same way as check mode, so the two never disagree about whether a
# run was complete.
if wanted psql-connection-strings; then
  for db in $(echo "$PG_DATABASES" | jq -r 'keys[]'); do
    arn=$(echo "$CONN_ARNS" | jq -r --arg k "$db" '.[$k] // empty')
    [[ -n "$arn" ]] && has_value "$arn" || STILL_EMPTY+=("psql-connection-string-${db}")
  done
fi
if wanted azure-openai-endpoint-definitions; then
  has_value "$ENDPOINT_ARN" || STILL_EMPTY+=("azure-openai-endpoint-definitions")
fi
if wanted s3-access-key; then
  has_value "$S3_KEY_ARN"    || STILL_EMPTY+=("s3-access-key-id")
  has_value "$S3_SECRET_ARN" || STILL_EMPTY+=("s3-secret-access-key")
fi

echo ""
echo "  seeded:  ${SEEDED}"
echo "  skipped: ${SKIPPED} (already had a value)"
(( LEFT_EMPTY > 0 )) && echo "  left empty: ${LEFT_EMPTY} (optional, no source configured)"
echo ""

if (( ${#STILL_EMPTY[@]} > 0 )); then
  warn "Still without a value:"
  for n in "${STILL_EMPTY[@]}"; do echo "    - $n"; done
  echo ""
  error "Seeding is incomplete. The workloads that read these will not start."
fi

log "Every required secret has a value."
info "Re-run with --check at any time to confirm this still holds."
