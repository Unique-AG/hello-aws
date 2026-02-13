#!/usr/bin/env bash
# validate-instance.sh — Verify no placeholder tokens remain after configure-instance.sh
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
  "<ZITADEL_PROJECT_ID>"
  "<ZITADEL_CLIENT_ID>"
  "<ZITADEL_ORG_ID>"
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

echo "Validating $ENV instance configuration ..."
echo ""

# ------------------------------------------------------------------
# Run checks
# ------------------------------------------------------------------
for token in "${PLACEHOLDERS[@]}"; do
  check_placeholder "$token"
done

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
if [[ "$ERRORS" -eq 0 ]]; then
  echo "OK: No placeholder tokens found in $ENV/. Instance is fully configured."
  exit 0
else
  echo "FAILED: $ERRORS placeholder token(s) still present in $ENV/."
  exit 1
fi
