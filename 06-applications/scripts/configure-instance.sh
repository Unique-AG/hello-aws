#!/usr/bin/env bash
# configure-instance.sh — Apply instance-specific values from instance-config.yaml
#
# Usage:
#   cd 06-applications
#   ./scripts/configure-instance.sh <env>
#   ./scripts/configure-instance.sh sbx
#
# Requires: yq (https://github.com/mikefarah/yq)
#
# This script is idempotent — safe to re-run. It tracks what values are
# currently applied (in <env>/.instance-applied.yaml) and replaces them with
# the values from <env>/instance-config.yaml.
#
# On first run against a fresh clone, the YAML files contain <PLACEHOLDER>
# tokens which are replaced with the real values from instance-config.yaml.
#
# Only files under the specified environment directory are modified — other
# environments on the same branch are not affected.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ------------------------------------------------------------------
# Environment argument
# ------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <env>"
  echo "  e.g. $0 sbx"
  exit 1
fi

ENV="$1"
ENV_DIR="$BASE_DIR/$ENV"
CONFIG="$ENV_DIR/instance-config.yaml"
STATE="$ENV_DIR/.instance-applied.yaml"

if [[ ! -d "$ENV_DIR" ]]; then
  echo "ERROR: Environment directory $ENV_DIR not found."
  exit 1
fi

# ------------------------------------------------------------------
# Preflight
# ------------------------------------------------------------------
if ! command -v yq &>/dev/null; then
  echo "ERROR: yq is required but not installed."
  echo "  brew install yq   OR   https://github.com/mikefarah/yq#install"
  exit 1
fi

if [[ ! -f "$CONFIG" ]]; then
  echo "ERROR: $CONFIG not found."
  echo "  cp instance-config.yaml.template $ENV/instance-config.yaml"
  echo "  # Edit $ENV/instance-config.yaml with your values"
  exit 1
fi

# ------------------------------------------------------------------
# Origin values (placeholder tokens for a fresh upstream clone)
# ------------------------------------------------------------------
origin_config() {
  cat <<'ORIGIN_EOF'
github:
  repoURL: "<GITHUB_REPO_URL>"
  targetRevision: "<GIT_TARGET_REVISION>"
domain:
  base: "<DOMAIN_BASE>"
  api: "<DOMAIN_API>"
  identity: "<DOMAIN_IDENTITY>"
  argocd: "<DOMAIN_ARGOCD>"
  dnsZone: "<DNS_ZONE>"
aws:
  region: "<AWS_REGION>"
  hostedZoneID: "<AWS_HOSTED_ZONE_ID>"
  kms:
    keyArn: "<KMS_KEY_ARN>"
  ecr:
    primary:
      accountId: "000000000000"
      prefix: uniquecr
    thirdParty:
      accountId: "000000000000"
      prefix: uniquecr
zitadel:
  projectId: "<ZITADEL_PROJECT_ID>"
  clientId: "<ZITADEL_CLIENT_ID>"
  orgId: "<ZITADEL_ORG_ID>"
ORIGIN_EOF
}

# ------------------------------------------------------------------
# Determine "from" values (state file if exists, else origin defaults)
# ------------------------------------------------------------------
if [[ -f "$STATE" ]]; then
  FROM="$STATE"
  echo "Using previously applied state from $ENV/.instance-applied.yaml"
else
  FROM_TMP=$(mktemp)
  origin_config > "$FROM_TMP"
  FROM="$FROM_TMP"
  echo "No state file found — using placeholder tokens"
fi

# ------------------------------------------------------------------
# Helper: check if a value is a placeholder token
# ------------------------------------------------------------------
is_placeholder() { [[ "$1" == "<"*">" ]]; }

# ------------------------------------------------------------------
# Read "from" (current) values
# ------------------------------------------------------------------
FROM_REPO_URL=$(yq '.github.repoURL' "$FROM")
FROM_TARGET_REV=$(yq '.github.targetRevision' "$FROM")
FROM_DOMAIN_BASE=$(yq '.domain.base' "$FROM")
FROM_DOMAIN_API=$(yq '.domain.api' "$FROM")
FROM_DOMAIN_IDENTITY=$(yq '.domain.identity' "$FROM")
FROM_DOMAIN_ARGOCD=$(yq '.domain.argocd' "$FROM")
FROM_DNS_ZONE=$(yq '.domain.dnsZone' "$FROM")
FROM_AWS_REGION=$(yq '.aws.region' "$FROM")
FROM_HOSTED_ZONE_ID=$(yq '.aws.hostedZoneID' "$FROM")
FROM_ECR_PRIMARY_ACCOUNT=$(yq '.aws.ecr.primary.accountId' "$FROM")
FROM_ECR_PRIMARY_PREFIX=$(yq '.aws.ecr.primary.prefix' "$FROM")
FROM_ECR_THIRDPARTY_ACCOUNT=$(yq '.aws.ecr.thirdParty.accountId' "$FROM")
FROM_ECR_THIRDPARTY_PREFIX=$(yq '.aws.ecr.thirdParty.prefix' "$FROM")
FROM_KMS_KEY_ARN=$(yq '.aws.kms.keyArn' "$FROM")
FROM_ZITADEL_PROJECT_ID=$(yq '.zitadel.projectId' "$FROM")
FROM_ZITADEL_CLIENT_ID=$(yq '.zitadel.clientId' "$FROM")
FROM_ZITADEL_ORG_ID=$(yq '.zitadel.orgId' "$FROM")

# Clean up temp file if used
[[ -v FROM_TMP ]] && rm -f "$FROM_TMP"

# Derived "from" values — handle placeholders vs real values
if is_placeholder "$FROM_AWS_REGION"; then
  # Placeholder mode: YAML files contain full placeholder tokens
  FROM_ECR_PRIMARY_FULL="<ECR_REGISTRY_PRIMARY>"
  FROM_ECR_THIRDPARTY_FULL="<ECR_REGISTRY_THIRDPARTY>"
  FROM_ECR_THIRDPARTY_BARE="<ECR_REGISTRY_THIRDPARTY_BARE>"
else
  # Real values: construct ECR URLs from components
  FROM_ECR_PRIMARY="${FROM_ECR_PRIMARY_ACCOUNT}.dkr.ecr.${FROM_AWS_REGION}.amazonaws.com"
  FROM_ECR_THIRDPARTY="${FROM_ECR_THIRDPARTY_ACCOUNT}.dkr.ecr.${FROM_AWS_REGION}.amazonaws.com"
  FROM_ECR_PRIMARY_FULL="${FROM_ECR_PRIMARY}/${FROM_ECR_PRIMARY_PREFIX}"
  FROM_ECR_THIRDPARTY_FULL="${FROM_ECR_THIRDPARTY}/${FROM_ECR_THIRDPARTY_PREFIX}"
  FROM_ECR_THIRDPARTY_BARE="${FROM_ECR_THIRDPARTY}"
fi

# ------------------------------------------------------------------
# Read "to" (desired) values from instance-config.yaml
# ------------------------------------------------------------------
TO_REPO_URL=$(yq '.github.repoURL' "$CONFIG")
TO_TARGET_REV=$(yq '.github.targetRevision' "$CONFIG")
TO_DOMAIN_BASE=$(yq '.domain.base' "$CONFIG")
TO_DOMAIN_API=$(yq '.domain.api' "$CONFIG")
TO_DOMAIN_IDENTITY=$(yq '.domain.identity' "$CONFIG")
TO_DOMAIN_ARGOCD=$(yq '.domain.argocd' "$CONFIG")
TO_DNS_ZONE=$(yq '.domain.dnsZone' "$CONFIG")
TO_AWS_REGION=$(yq '.aws.region' "$CONFIG")
TO_HOSTED_ZONE_ID=$(yq '.aws.hostedZoneID' "$CONFIG")
TO_ECR_PRIMARY_ACCOUNT=$(yq '.aws.ecr.primary.accountId' "$CONFIG")
TO_ECR_PRIMARY_PREFIX=$(yq '.aws.ecr.primary.prefix' "$CONFIG")
TO_ECR_THIRDPARTY_ACCOUNT=$(yq '.aws.ecr.thirdParty.accountId' "$CONFIG")
TO_ECR_THIRDPARTY_PREFIX=$(yq '.aws.ecr.thirdParty.prefix' "$CONFIG")
TO_KMS_KEY_ARN=$(yq '.aws.kms.keyArn' "$CONFIG")
TO_ZITADEL_PROJECT_ID=$(yq '.zitadel.projectId' "$CONFIG")
TO_ZITADEL_CLIENT_ID=$(yq '.zitadel.clientId' "$CONFIG")
TO_ZITADEL_ORG_ID=$(yq '.zitadel.orgId' "$CONFIG")

# Derived "to" values (always real — instance-config has actual values)
TO_ECR_PRIMARY="${TO_ECR_PRIMARY_ACCOUNT}.dkr.ecr.${TO_AWS_REGION}.amazonaws.com"
TO_ECR_THIRDPARTY="${TO_ECR_THIRDPARTY_ACCOUNT}.dkr.ecr.${TO_AWS_REGION}.amazonaws.com"
TO_ECR_PRIMARY_FULL="${TO_ECR_PRIMARY}/${TO_ECR_PRIMARY_PREFIX}"
TO_ECR_THIRDPARTY_FULL="${TO_ECR_THIRDPARTY}/${TO_ECR_THIRDPARTY_PREFIX}"

# ------------------------------------------------------------------
# Helper: sed replacement (portable macOS + Linux)
# ------------------------------------------------------------------
do_sed() {
  local pattern="$1"
  shift
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' "$pattern" "$@"
  else
    sed -i "$pattern" "$@"
  fi
}

# Replace a string in all YAML files under the environment directory
# (excluding instance-config.yaml and .instance-applied.yaml)
replace_all() {
  local old="$1"
  local new="$2"

  if [[ "$old" == "$new" ]]; then
    return 0
  fi

  # Escape special characters for sed
  local old_escaped new_escaped
  old_escaped=$(printf '%s\n' "$old" | sed 's/[&/\]/\\&/g')
  new_escaped=$(printf '%s\n' "$new" | sed 's/[&/\]/\\&/g')

  while IFS= read -r -d '' file; do
    if grep -qF "$old" "$file"; then
      do_sed "s|${old_escaped}|${new_escaped}|g" "$file"
    fi
  done < <(find "$ENV_DIR" -name '*.yaml' \
    -not -name 'instance-config.yaml' \
    -not -name '.instance-applied.yaml' \
    -print0)
}

# ------------------------------------------------------------------
# Apply replacements (order matters — longest/most-specific first)
# ------------------------------------------------------------------
echo "Configuring $ENV from $CONFIG ..."

# 1. ECR registries (full registry URL including prefix — must be before region replacement)
echo "  ECR primary registry ..."
replace_all "$FROM_ECR_PRIMARY_FULL" "$TO_ECR_PRIMARY_FULL"

echo "  ECR third-party registry ..."
replace_all "$FROM_ECR_THIRDPARTY_FULL" "$TO_ECR_THIRDPARTY_FULL"

# Also handle bare registry references (without prefix, e.g. in _common.yaml)
echo "  ECR third-party bare registry ..."
replace_all "$FROM_ECR_THIRDPARTY_BARE" "$TO_ECR_THIRDPARTY"

# 2. KMS key ARN (before region, since ARN contains region)
echo "  KMS key ARN ..."
replace_all "$FROM_KMS_KEY_ARN" "$TO_KMS_KEY_ARN"

# 3. Repository URL (before domain, since URL contains github.com not our domain)
echo "  Repository URL ..."
replace_all "$FROM_REPO_URL" "$TO_REPO_URL"

# 4. Target revision in app specs
if [[ "$FROM_TARGET_REV" != "$TO_TARGET_REV" ]]; then
  echo "  Target revision ..."
  while IFS= read -r -d '' file; do
    if grep -qF "$TO_REPO_URL" "$file" || grep -qF "targetRevision:" "$file" || grep -qF "revision:" "$file"; then
      do_sed "s|revision: ${FROM_TARGET_REV}|revision: ${TO_TARGET_REV}|g" "$file"
      do_sed "s|targetRevision: ${FROM_TARGET_REV}|targetRevision: ${TO_TARGET_REV}|g" "$file"
    fi
  done < <(find "$ENV_DIR" -name '*.yaml' \
    -not -name 'instance-config.yaml' \
    -not -name '.instance-applied.yaml' \
    -print0)
fi

# 5. Domains (longest/most-specific first to avoid partial matches)
echo "  ArgoCD domain ..."
replace_all "$FROM_DOMAIN_ARGOCD" "$TO_DOMAIN_ARGOCD"

echo "  API domain ..."
replace_all "$FROM_DOMAIN_API" "$TO_DOMAIN_API"

echo "  Identity domain ..."
replace_all "$FROM_DOMAIN_IDENTITY" "$TO_DOMAIN_IDENTITY"

echo "  Base domain ..."
replace_all "$FROM_DOMAIN_BASE" "$TO_DOMAIN_BASE"

echo "  DNS zone ..."
replace_all "$FROM_DNS_ZONE" "$TO_DNS_ZONE"

# 6. AWS region (standalone references not already handled by ECR/KMS replacement)
echo "  AWS region ..."
replace_all "$FROM_AWS_REGION" "$TO_AWS_REGION"

# 7. Hosted zone ID
echo "  Hosted zone ID ..."
replace_all "$FROM_HOSTED_ZONE_ID" "$TO_HOSTED_ZONE_ID"

# 8. Zitadel IDs
echo "  Zitadel project ID ..."
replace_all "$FROM_ZITADEL_PROJECT_ID" "$TO_ZITADEL_PROJECT_ID"

echo "  Zitadel client ID ..."
replace_all "$FROM_ZITADEL_CLIENT_ID" "$TO_ZITADEL_CLIENT_ID"

echo "  Zitadel org ID ..."
replace_all "$FROM_ZITADEL_ORG_ID" "$TO_ZITADEL_ORG_ID"

# ------------------------------------------------------------------
# Save applied state
# ------------------------------------------------------------------
cp "$CONFIG" "$STATE"
echo ""
echo "Done. State saved to $ENV/.instance-applied.yaml"
echo "Run ./scripts/validate-instance.sh $ENV to verify."
