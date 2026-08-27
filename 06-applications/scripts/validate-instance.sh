#!/usr/bin/env bash
# validate-instance.sh — Verify no placeholder tokens remain after configure-instance.sh
# (checks both the applications YAML files and the Terraform tfvars it rewrites)
#
# Usage:
#   cd 06-applications
#   ./scripts/validate-instance.sh <env>
#   ./scripts/validate-instance.sh sbx
#
# Exit code 0 = clean, 1 = placeholder tokens still present

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

if [[ ! -d "$ENV_DIR" ]]; then
  echo "ERROR: Environment directory $ENV_DIR not found."
  exit 1
fi

ERRORS=0

# ------------------------------------------------------------------
# Placeholder tokens to check for (must not appear in configured files)
# ------------------------------------------------------------------
PLACEHOLDERS=(
  "<GITHUB_REPO_URL>"
  "<GIT_TARGET_REVISION>"
  "<DOMAIN_BASE>"
  "<DOMAIN_API>"
  "<DOMAIN_IDENTITY>"
  "<DOMAIN_ARGOCD>"
  "<DNS_ZONE>"
  "<AWS_REGION>"
  "<AWS_HOSTED_ZONE_ID>"
  "<ECR_REGISTRY_PRIMARY>"
  "<ECR_REGISTRY_THIRDPARTY>"
  "<ECR_REGISTRY_THIRDPARTY_BARE>"
  "<KMS_KEY_ARN>"
  "<EKS_CLUSTER_NAME>"
  "<VPC_ID>"
  "<TARGET_GROUP_HTTP_ARN>"
  "<TARGET_GROUP_HTTPS_ARN>"
  "<ZITADEL_PROJECT_ID>"
  "<ZITADEL_CLIENT_ID>"
  "<ZITADEL_ORG_ID>"
  "<AWS_ACCOUNT_ID>"
  "<REDIS_URL>"
  "<BEDROCK_COHERE_EMBED_V4_PROFILE_ID>"
  "<ROUTE53_PRIVATE_ZONE_ID>"
  "<CONNECTIVITY_ACCOUNT_ID>"
  "<EFS_DOCLING_MODELS_ID>"
  "<BEDROCK_MINIMAX_REGION>"
  "<AMP_WORKSPACE_ID>"
  "<AMP_REMOTE_WRITE_URL>"
  "<OBSERVABILITY_S3_BUCKET_NAME>"
)

# ------------------------------------------------------------------
# Helper: check for a placeholder token in YAML files under the env dir
# (excluding instance-config.yaml, .instance-applied.yaml)
# ------------------------------------------------------------------
check_placeholder() {
  local token="$1"

  local matches
  matches=$(grep -rl --include='*.yaml' -F "$token" "$ENV_DIR" \
    | grep -v 'instance-config.yaml' \
    | grep -v '.instance-applied.yaml' \
    || true)

  if [[ -n "$matches" ]]; then
    echo "FAIL: $token still found in:"
    while IFS= read -r match; do
      printf '  %s\n' "$match"
    done <<< "$matches"
    echo ""
    ERRORS=$((ERRORS + 1))
  fi
}

# ------------------------------------------------------------------
# Dummy values that must not survive in Terraform tfvars.
#
# Unlike the YAML files, the tfvars carry concrete dummy values rather than
# angle-bracket tokens, so they are checked separately. Leaving them in place
# is silent: a stale ACR entry, for example, is dropped by the contains()
# filter in 05-compute/terraform/ecr.tf and the cluster simply cannot pull
# application images.
# ------------------------------------------------------------------
PROJECT_ROOT="$(cd "$BASE_DIR/.." && pwd)"

TFVARS_PLACEHOLDERS=(
  "example.azurecr.io"
  # The bare ACR alias is a list element, matched with its quotes and comma so
  # the word "example" in a comment does not trip the check.
  '"example",'
  "sbx.example.com"
  "Z0000000000000000000"
)

# The same file set configure-instance.sh rewrites.
tfvars_files() {
  find "$PROJECT_ROOT" -path "*/terraform/environments/$ENV/*.auto.tfvars" -print0
  if [[ -f "$PROJECT_ROOT/common.auto.tfvars" ]]; then
    printf '%s\0' "$PROJECT_ROOT/common.auto.tfvars"
  fi
}

check_tfvars_placeholder() {
  local token="$1"

  local matches=""
  while IFS= read -r -d '' file; do
    if grep -qF "$token" "$file"; then
      matches+="  ${file#"$PROJECT_ROOT/"}"$'\n'
    fi
  done < <(tfvars_files)

  if [[ -n "$matches" ]]; then
    echo "FAIL: $token still found in:"
    printf '%s' "$matches"
    echo ""
    ERRORS=$((ERRORS + 1))
  fi
}

echo "Validating $ENV instance configuration ..."
echo ""

# ------------------------------------------------------------------
# Run checks
# ------------------------------------------------------------------
for token in "${PLACEHOLDERS[@]}"; do
  check_placeholder "$token"
done

for token in "${TFVARS_PLACEHOLDERS[@]}"; do
  check_tfvars_placeholder "$token"
done

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
if [[ "$ERRORS" -eq 0 ]]; then
  echo "OK: No placeholder tokens found in $ENV/ or the $ENV tfvars. Instance is fully configured."
  exit 0
else
  echo "FAILED: $ERRORS placeholder token(s) still present."
  exit 1
fi
