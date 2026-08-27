#!/bin/bash
set -euo pipefail

#######################################
# Deploy with ACR Credentials
#######################################
#
# Wrapper around deploy.sh that retrieves ACR credentials from 1Password and
# writes them into the Secrets Manager secret backing the ECR pull-through
# cache rules.
#
# The credentials are NOT passed to Terraform. Terraform owns the secret
# *container* (aws_secretsmanager_secret.acr_credentials, named
# ecr-pullthroughcache/<registry-url>); the *value* is written here with the
# AWS CLI, so it never enters Terraform state or a plan file. This matches the
# convention in 04-data-and-ai/terraform/secrets.tf and the ACR entry in
# docs/security-baseline.md.
#
# Because Terraform creates the container, the value is written AFTER the
# deploy completes -- on a first deploy the secret does not exist beforehand.
# Re-running this is how the credentials are rotated: put-secret-value adds a
# new version against the same ARN, so the pull-through cache rules keep
# working without any Terraform change.
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

# Checked up front rather than after the deploy: the credential write happens
# once Terraform has already applied, and failing there would leave the cache
# rules pointing at a secret with no usable version.
for cmd in aws jq terraform; do
  if ! command -v "$cmd" &>/dev/null; then
    echo -e "${RED}Error: ${cmd} is required but not installed${NC}"
    exit 1
  fi
done

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

# Run the deploy first: Terraform creates the secret container, and on a first
# deploy it does not exist until then.
#
# Deliberately not `exec` -- the credential write below has to happen after
# deploy.sh returns. Previously this exported TF_VAR_acr_username /
# TF_VAR_acr_password and exec'd; deploy.sh turns every TF_VAR_* into an
# explicit -var=, and neither variable is declared in 05-compute, so Terraform
# rejected them and this script could not even plan.
"${SCRIPT_DIR}/deploy.sh" "$LAYER" "$ENV" "${DEPLOY_ARGS[@]+"${DEPLOY_ARGS[@]}"}"

# Only the compute layer owns the ACR secret.
if [[ "$LAYER" != "compute" ]]; then
  exit 0
fi

echo -e "${YELLOW}Writing ACR credentials to Secrets Manager ...${NC}"

TERRAFORM_DIR="${SCRIPT_DIR}/../05-compute/terraform"
ACR_SECRET_ARN=$(cd "$TERRAFORM_DIR" && terraform output -raw acr_secret_arn 2>/dev/null) || ACR_SECRET_ARN=""

if [[ -z "$ACR_SECRET_ARN" || "$ACR_SECRET_ARN" == "null" ]]; then
  echo -e "${RED}Error: could not read the acr_secret_arn output from ${TERRAFORM_DIR}${NC}"
  echo -e "${YELLOW}ACR credentials were NOT written. Pull-through cache auth will fail.${NC}"
  echo -e "${YELLOW}Check that acr_registry_url is set in common.auto.tfvars.${NC}"
  exit 1
fi

# JSON with "username" and "password" -- the shape ECR expects for a
# pull-through cache credential (see 05-compute/terraform/ecr.tf).
# Built with jq so credentials containing quotes or backslashes are escaped.
ACR_SECRET_JSON=$(jq -n --arg u "$ACR_USERNAME" --arg p "$ACR_PASSWORD" '{username: $u, password: $p}')

aws secretsmanager put-secret-value \
  --secret-id "$ACR_SECRET_ARN" \
  --secret-string "$ACR_SECRET_JSON" \
  --output text --query 'VersionId' >/dev/null

echo -e "${GREEN}ACR credentials written to ${ACR_SECRET_ARN}${NC}"
