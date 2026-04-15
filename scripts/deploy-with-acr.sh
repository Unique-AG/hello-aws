#!/bin/bash
set -euo pipefail

#######################################
# Deploy with ACR Credentials
#######################################
#
# Wrapper around deploy.sh that retrieves ACR credentials from 1Password
# and passes them as ephemeral TF_VAR_* environment variables.
#
# Usage:
#   ./scripts/deploy-with-acr.sh <layer> <environment> [1password-item] [deploy-args...]
#
# Examples:
#   ./scripts/deploy-with-acr.sh compute sbx
#   ./scripts/deploy-with-acr.sh compute sbx "azurecr" --auto-approve
#   ./scripts/deploy-with-acr.sh compute prod "ACR Prod" --auto-approve --skip-plan
#
# The 1Password item should contain:
#   - username field: ACR access key username
#   - password/credential field: ACR access key password
#
# Default 1Password item: "azurecr"
#######################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Parse arguments
LAYER="${1:-}"
ENV="${2:-}"
OP_ITEM="${3:-azurecr}"
shift 3 2>/dev/null || true
DEPLOY_ARGS=("${@+"$@"}")

if [[ -z "$LAYER" || -z "$ENV" ]]; then
  echo -e "${RED}Error: Layer and environment are required${NC}"
  echo -e "${YELLOW}Usage: ./scripts/deploy-with-acr.sh <layer> <environment> [1password-item] [deploy-args...]${NC}"
  exit 1
fi

# Check if the third argument looks like a flag (starts with --)
# If so, treat it as a deploy arg, not a 1Password item
if [[ "$OP_ITEM" == --* ]]; then
  DEPLOY_ARGS=("$OP_ITEM" "${DEPLOY_ARGS[@]+"${DEPLOY_ARGS[@]}"}")
  OP_ITEM="azurecr"
fi

# Check 1Password CLI
if ! command -v op &>/dev/null; then
  echo -e "${RED}Error: 1Password CLI (op) is not installed${NC}"
  echo -e "${YELLOW}Install: https://developer.1password.com/docs/cli/get-started/${NC}"
  exit 1
fi

# Retrieve ACR credentials from 1Password
echo -e "${YELLOW}Retrieving ACR credentials from 1Password item: ${OP_ITEM}${NC}"

ACR_USERNAME=$(op item get "$OP_ITEM" --fields username 2>/dev/null) || {
  echo -e "${RED}Error: Failed to retrieve ACR username from 1Password item '${OP_ITEM}'${NC}"
  echo -e "${YELLOW}Make sure you are signed in: op signin${NC}"
  exit 1
}

ACR_PASSWORD=$(op item get "$OP_ITEM" --fields password 2>/dev/null) || {
  echo -e "${RED}Error: Failed to retrieve ACR password from 1Password item '${OP_ITEM}'${NC}"
  exit 1
}

if [[ -z "$ACR_USERNAME" || -z "$ACR_PASSWORD" ]]; then
  echo -e "${RED}Error: ACR credentials are empty${NC}"
  exit 1
fi

echo -e "${GREEN}ACR credentials retrieved successfully${NC}"

# Export as TF_VAR_* for deploy.sh to pick up
export TF_VAR_acr_username="$ACR_USERNAME"
export TF_VAR_acr_password="$ACR_PASSWORD"

# Delegate to deploy.sh
exec "${SCRIPT_DIR}/deploy.sh" "$LAYER" "$ENV" "${DEPLOY_ARGS[@]+"${DEPLOY_ARGS[@]}"}"
