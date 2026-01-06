#!/bin/bash
# Validation script to check all backend-config.hcl files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

ENV="${1:-sbx}"

echo "Validating backend-config.hcl files for environment: ${ENV}"
echo "Project root: ${PROJECT_ROOT}"
echo ""

# Expected values (these would come from bootstrap outputs in real scenario)
S3_BUCKET="s3-acme-dogfood-x-euc2-tfstate"
DYNAMODB_TABLE="dynamodb-acme-dogfood-sbx-euc2-tfstate-lock"
KMS_ALIAS="alias/kms-acme-dogfood-sbx-euc2-tfstate"
REGION="eu-central-2"

# Expected state keys (using function instead of associative array for compatibility)
get_expected_state_key() {
  case "$1" in
    "01-bootstrap") echo "bootstrap/terraform.tfstate" ;;
    "02-governance") echo "governance/terraform.tfstate" ;;
    "03-infrastructure") echo "infrastructure/terraform.tfstate" ;;
    "04-data-and-ai") echo "data-and-ai/terraform.tfstate" ;;
    "05-compute") echo "compute/terraform.tfstate" ;;
    "06-applications") echo "applications/terraform.tfstate" ;;
    *) echo "" ;;
  esac
}

VALID_COUNT=0
INVALID_COUNT=0
MISSING_COUNT=0

echo "Checking backend-config.hcl files..."
echo ""

for LAYER_DIR in "${PROJECT_ROOT}"/0*-*/terraform; do
  if [[ ! -d "$LAYER_DIR" ]]; then
    continue
  fi
  
  LAYER_NAME=$(basename "$(dirname "$LAYER_DIR")")
  BACKEND_CONFIG_FILE="${LAYER_DIR}/environments/${ENV}/backend-config.hcl"
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Layer: ${LAYER_NAME}"
  echo "File: ${BACKEND_CONFIG_FILE}"
  
  if [[ ! -f "$BACKEND_CONFIG_FILE" ]]; then
    echo "❌ MISSING: File does not exist"
    ((MISSING_COUNT++))
    echo ""
    continue
  fi
  
  # Extract values from file
  FILE_BUCKET=$(grep -E "^bucket\s*=" "$BACKEND_CONFIG_FILE" | sed 's/.*=\s*"\(.*\)".*/\1/' | tr -d ' ' || echo "")
  FILE_KEY=$(grep -E "^key\s*=" "$BACKEND_CONFIG_FILE" | sed 's/.*=\s*"\(.*\)".*/\1/' | tr -d ' ' || echo "")
  FILE_REGION=$(grep -E "^region\s*=" "$BACKEND_CONFIG_FILE" | sed 's/.*=\s*"\(.*\)".*/\1/' | tr -d ' ' || echo "")
  FILE_DYNAMODB=$(grep -E "^dynamodb_table\s*=" "$BACKEND_CONFIG_FILE" | sed 's/.*=\s*"\(.*\)".*/\1/' | tr -d ' ' || echo "")
  FILE_KMS=$(grep -E "^kms_key_id\s*=" "$BACKEND_CONFIG_FILE" | sed 's/.*=\s*"\(.*\)".*/\1/' | tr -d ' ' || echo "")
  
  EXPECTED_KEY=$(get_expected_state_key "$LAYER_NAME")
  
  # Validate
  ERRORS=()
  
  if [[ -z "$FILE_BUCKET" ]] || [[ "$FILE_BUCKET" == '""' ]]; then
    ERRORS+=("bucket is empty or not set")
  fi
  
  if [[ -z "$FILE_KEY" ]] || [[ "$FILE_KEY" == '""' ]]; then
    ERRORS+=("key is empty or not set")
  elif [[ -n "$EXPECTED_KEY" ]] && [[ "$FILE_KEY" != "$EXPECTED_KEY" ]]; then
    ERRORS+=("key mismatch: expected '${EXPECTED_KEY}', got '${FILE_KEY}'")
  fi
  
  if [[ -z "$FILE_REGION" ]] || [[ "$FILE_REGION" == '""' ]]; then
    ERRORS+=("region is empty or not set")
  fi
  
  if [[ -z "$FILE_DYNAMODB" ]] || [[ "$FILE_DYNAMODB" == '""' ]]; then
    ERRORS+=("dynamodb_table is empty or not set")
  fi
  
  if [[ -z "$FILE_KMS" ]] || [[ "$FILE_KMS" == '""' ]]; then
    ERRORS+=("kms_key_id is empty or not set")
  fi
  
  if [[ ${#ERRORS[@]} -eq 0 ]]; then
    echo "✅ VALID"
    echo "   bucket: ${FILE_BUCKET}"
    echo "   key: ${FILE_KEY}"
    echo "   region: ${FILE_REGION}"
    echo "   dynamodb_table: ${FILE_DYNAMODB}"
    echo "   kms_key_id: ${FILE_KMS}"
    ((VALID_COUNT++))
  else
    echo "❌ INVALID:"
    for error in "${ERRORS[@]}"; do
      echo "   - ${error}"
    done
    echo "   Current values:"
    echo "     bucket: ${FILE_BUCKET:-<empty>}"
    echo "     key: ${FILE_KEY:-<empty>}"
    echo "     region: ${FILE_REGION:-<empty>}"
    echo "     dynamodb_table: ${FILE_DYNAMODB:-<empty>}"
    echo "     kms_key_id: ${FILE_KMS:-<empty>}"
    ((INVALID_COUNT++))
  fi
  echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Summary:"
echo "  ✅ Valid: ${VALID_COUNT}"
echo "  ❌ Invalid: ${INVALID_COUNT}"
echo "  ⚠️  Missing: ${MISSING_COUNT}"
echo ""

if [[ $INVALID_COUNT -gt 0 ]] || [[ $MISSING_COUNT -gt 0 ]]; then
  exit 1
fi

