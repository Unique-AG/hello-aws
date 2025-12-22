#!/bin/bash
set -euo pipefail

#######################################
# Validate Backend Configuration Files
#######################################
#
# This script validates that all backend-config.hcl files have the correct
# bucket name matching the bootstrap layer's terraform output.
#
# Usage:
#   ./scripts/validate-backend-configs.sh.sh [environment]
#
# Examples:
#   ./scripts/validate-backend-configs.sh.sh sbx
#   ./scripts/validate-backend-configs.sh.sh dev
#######################################

# Get the script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
ENV="${1:-sbx}"

# Validate environment
if [[ ! "$ENV" =~ ^(dev|test|prod|sbx)$ ]]; then
  echo -e "${RED}❌ Error: Environment must be one of: dev, test, prod, sbx${NC}"
  exit 1
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🔍 Validating Backend Configuration Files${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Environment: ${ENV}${NC}"
echo ""

# Get expected bucket name from bootstrap layer terraform output
BOOTSTRAP_TERRAFORM_DIR="${PROJECT_ROOT}/01-bootstrap/terraform"
BOOTSTRAP_BACKEND_CONFIG="${BOOTSTRAP_TERRAFORM_DIR}/environments/${ENV}/backend-config.hcl"

if [[ ! -f "$BOOTSTRAP_BACKEND_CONFIG" ]]; then
  echo -e "${RED}❌ Error: Bootstrap backend config not found: ${BOOTSTRAP_BACKEND_CONFIG}${NC}"
  exit 1
fi

# Extract bucket name from bootstrap backend config
EXPECTED_BUCKET=$(grep -E '^bucket\s*=' "$BOOTSTRAP_BACKEND_CONFIG" | awk -F'"' '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || echo "")

if [[ -z "$EXPECTED_BUCKET" ]]; then
  echo -e "${RED}❌ Error: Could not extract bucket name from bootstrap backend config${NC}"
  exit 1
fi

echo -e "${GREEN}✅ Expected bucket name: ${EXPECTED_BUCKET}${NC}"
echo ""

# Validate all layers
ERROR_COUNT=0
VALID_COUNT=0
MISSING_COUNT=0

for LAYER_DIR in "${PROJECT_ROOT}"/0*-*/terraform; do
  if [[ ! -d "$LAYER_DIR" ]]; then
    continue
  fi
  
  LAYER_NAME=$(basename "$(dirname "$LAYER_DIR")")
  BACKEND_CONFIG_FILE="${LAYER_DIR}/environments/${ENV}/backend-config.hcl"
  
  if [[ ! -f "$BACKEND_CONFIG_FILE" ]]; then
    echo -e "${YELLOW}   ⏭️  ${LAYER_NAME}: backend-config.hcl not found${NC}"
    MISSING_COUNT=$((MISSING_COUNT + 1))
    continue
  fi
  
  # Extract bucket name from this layer's backend config
  ACTUAL_BUCKET=$(grep -E '^bucket\s*=' "$BACKEND_CONFIG_FILE" | awk -F'"' '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || echo "")
  
  if [[ -z "$ACTUAL_BUCKET" ]]; then
    echo -e "${RED}   ❌ ${LAYER_NAME}: No bucket name found${NC}"
    ERROR_COUNT=$((ERROR_COUNT + 1))
  elif [[ "$ACTUAL_BUCKET" != "$EXPECTED_BUCKET" ]]; then
    echo -e "${RED}   ❌ ${LAYER_NAME}: Bucket mismatch${NC}"
    echo -e "${RED}      Expected: ${EXPECTED_BUCKET}${NC}"
    echo -e "${RED}      Actual:   ${ACTUAL_BUCKET}${NC}"
    ERROR_COUNT=$((ERROR_COUNT + 1))
  else
    echo -e "${GREEN}   ✅ ${LAYER_NAME}: Correct${NC}"
    VALID_COUNT=$((VALID_COUNT + 1))
  fi
done

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [[ $ERROR_COUNT -eq 0 ]]; then
  echo -e "${GREEN}✅ Validation Passed!${NC}"
  echo -e "${GREEN}   Valid: ${VALID_COUNT}${NC}"
  if [[ $MISSING_COUNT -gt 0 ]]; then
    echo -e "${YELLOW}   Missing: ${MISSING_COUNT}${NC}"
  fi
  exit 0
else
  echo -e "${RED}❌ Validation Failed!${NC}"
  echo -e "${RED}   Errors: ${ERROR_COUNT}${NC}"
  echo -e "${GREEN}   Valid: ${VALID_COUNT}${NC}"
  if [[ $MISSING_COUNT -gt 0 ]]; then
    echo -e "${YELLOW}   Missing: ${MISSING_COUNT}${NC}"
  fi
  echo ""
  echo -e "${YELLOW}💡 To fix, run the bootstrap script:${NC}"
  echo -e "${YELLOW}   ./01-bootstrap/scripts/bootstrap.sh ${ENV}${NC}"
  exit 1
fi
