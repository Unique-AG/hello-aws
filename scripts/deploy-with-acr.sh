#!/usr/bin/env bash
#######################################
# Deploy with ACR credentials from 1Password
#######################################
# Retrieves ACR credentials from 1Password and deploys compute layer
#
# Usage:
#   ./scripts/deploy-with-acr.sh <layer> <env> [1password-item] [deploy-args...]
#
# Examples:
#   ./scripts/deploy-with-acr.sh compute sbx --auto-approve
#   ./scripts/deploy-with-acr.sh compute sbx azurecr --auto-approve
#   ./scripts/deploy-with-acr.sh compute sbx --skip-plan --auto-approve
#######################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
info()  { echo -e "${BLUE}[i]${NC} $1"; }

LAYER="${1:-}"
ENV="${2:-sbx}"
OP_ITEM="azurecr"

# Parse optional 1Password item name (if 3rd arg is not a flag)
if [ -n "${3:-}" ] && [[ ! "${3}" =~ ^-- ]]; then
  OP_ITEM="$3"
  shift 3
else
  shift 2 || true
fi

# Remaining arguments will be passed to deploy script
# Use array only if there are arguments to avoid unbound variable error with set -u
if [ $# -gt 0 ]; then
  DEPLOY_ARGS=("$@")
else
  DEPLOY_ARGS=()
fi

if [ -z "$LAYER" ]; then
  error "Usage: $0 <layer> <env> [1password-item] [deploy-args...]"
fi

# Check 1Password CLI
if ! command -v op &> /dev/null; then
  error "1Password CLI (op) not found. Install from: https://developer.1password.com/docs/cli/get-started"
fi

# Check if signed in to 1Password
if ! op account list &>/dev/null; then
  warn "Not signed in to 1Password. Signing in..."
  op signin
fi

OP_VAULT="Employee"
info "Retrieving ACR credentials from 1Password item: ${OP_ITEM} (vault: ${OP_VAULT})"

# Check for jq
if ! command -v jq &> /dev/null; then
  error "jq is required. Install with: brew install jq"
fi

# Get ACR credentials from 1Password using JSON output
OP_ITEM_JSON=$(op item get "${OP_ITEM}" --vault "${OP_VAULT}" --format json 2>/dev/null)

if [ -z "$OP_ITEM_JSON" ]; then
  error "Could not retrieve item '${OP_ITEM}' from vault '${OP_VAULT}'"
fi

# Extract credentials from JSON
ACR_USERNAME=$(echo "$OP_ITEM_JSON" | jq -r '.fields[] | select(.label=="username" or .purpose=="USERNAME") | .value' | head -1)
ACR_PASSWORD=$(echo "$OP_ITEM_JSON" | jq -r '.fields[] | select(.label=="password" or .purpose=="PASSWORD") | .value' | head -1)

# Registry URL is not a secret - use the known value
ACR_REGISTRY_URL="uniquecr.azurecr.io"

if [ -z "$ACR_USERNAME" ] || [ -z "$ACR_PASSWORD" ]; then
  error "Could not retrieve ACR credentials from 1Password. Check item name and field labels."
fi

log "ACR credentials retrieved"

# Export as Terraform variables
export TF_VAR_acr_registry_url="$ACR_REGISTRY_URL"
export TF_VAR_acr_username="$ACR_USERNAME"
export TF_VAR_acr_password="$ACR_PASSWORD"

# Pass all remaining arguments to the deploy script
# The deploy script will handle secret restoration and KMS key cancellation in Step 3.5
cd "$PROJECT_ROOT"
if [ ${#DEPLOY_ARGS[@]} -gt 0 ]; then
  ./scripts/deploy.sh "$LAYER" "$ENV" "${DEPLOY_ARGS[@]}"
else
  ./scripts/deploy.sh "$LAYER" "$ENV"
fi
