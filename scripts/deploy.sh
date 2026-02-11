#!/bin/bash
set -euo pipefail

#######################################
# Terraform Deployment Script
#######################################
#
# This script deploys Terraform configuration by:
# 1. Initializing Terraform
# 2. Validating configuration
# 3. Planning changes
# 4. Applying changes
#
# Usage:
#   ./scripts/deploy [layer] [environment] [--auto-approve] [--skip-plan]
#
# Examples:
#   ./scripts/deploy governance sbx
#   ./scripts/deploy governance dev --auto-approve
#   ./scripts/deploy infrastructure prod --skip-plan --auto-approve
#   ./scripts/deploy bootstrap sbx
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
LAYER="${1:-}"
ENV="${2:-dev}"
AUTO_APPROVE=false
SKIP_PLAN=false

for arg in "$@"; do
  case $arg in
    --auto-approve)
      AUTO_APPROVE=true
      ;;
    --skip-plan)
      SKIP_PLAN=true
      ;;
  esac
done

# Validate arguments
if [[ -z "$LAYER" ]]; then
  echo -e "${RED}❌ Error: Layer is required${NC}"
  echo -e "${YELLOW}   Usage: ./scripts/deploy [layer] [environment] [--auto-approve] [--skip-plan]${NC}"
  echo -e "${YELLOW}   Examples:${NC}"
  echo -e "${YELLOW}     ./scripts/deploy bootstrap sbx${NC}"
  echo -e "${YELLOW}     ./scripts/deploy governance dev --auto-approve${NC}"
  echo -e "${YELLOW}     ./scripts/deploy infrastructure prod --skip-plan --auto-approve${NC}"
  exit 1
fi

# Validate environment
if [[ ! "$ENV" =~ ^(dev|test|prod|sbx)$ ]]; then
  echo -e "${RED}❌ Error: Environment must be one of: dev, test, prod, sbx${NC}"
  exit 1
fi

# Function to get layer directory name (bash 3.x compatible)
get_layer_dir_name() {
  case "$1" in
    "bootstrap") echo "01-bootstrap" ;;
    "governance") echo "02-governance" ;;
    "infrastructure") echo "03-infrastructure" ;;
    "data-and-ai") echo "04-data-and-ai" ;;
    "compute") echo "05-compute" ;;
    "applications") echo "06-applications" ;;
    *) echo "" ;;
  esac
}

# Get layer directory
LAYER_DIR_NAME=$(get_layer_dir_name "$LAYER")
if [[ -z "$LAYER_DIR_NAME" ]]; then
  echo -e "${YELLOW}⚠️  Warning: Layer '${LAYER}' not in standard mapping, trying direct lookup...${NC}"
  # Try to find layer directory by pattern
  LAYER_DIR_NAME=$(find "$PROJECT_ROOT" -maxdepth 1 -type d -name "*${LAYER}*" -o -name "${LAYER}" | head -1 | xargs basename 2>/dev/null || echo "")
  if [[ -z "$LAYER_DIR_NAME" ]]; then
    echo -e "${RED}❌ Error: Could not find layer directory for '${LAYER}'${NC}"
    echo -e "${YELLOW}   Available layers: bootstrap, governance, infrastructure, data-and-ai, compute, applications${NC}"
    exit 1
  fi
fi

LAYER_DIR="${PROJECT_ROOT}/${LAYER_DIR_NAME}"
TERRAFORM_DIR="${LAYER_DIR}/terraform"

CONFIG_FILE="${TERRAFORM_DIR}/environments/${ENV}/00-config.auto.tfvars"
BACKEND_CONFIG="${TERRAFORM_DIR}/environments/${ENV}/backend-config.hcl"
COMMON_CONFIG="${PROJECT_ROOT}/common.auto.tfvars"

# Check if terraform directory exists
if [[ ! -d "$TERRAFORM_DIR" ]]; then
  echo -e "${RED}❌ Error: Terraform directory not found: ${TERRAFORM_DIR}${NC}"
  exit 1
fi

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo -e "${RED}❌ Error: Config file not found: ${CONFIG_FILE}${NC}"
  exit 1
fi

# Check if common config exists
if [[ ! -f "$COMMON_CONFIG" ]]; then
  echo -e "${RED}❌ Error: Common config file not found: ${COMMON_CONFIG}${NC}"
  exit 1
fi

# Check if backend config exists
if [[ ! -f "$BACKEND_CONFIG" ]]; then
  echo -e "${RED}❌ Error: Backend config file not found: ${BACKEND_CONFIG}${NC}"
  echo -e "${YELLOW}   Please update backend-config.hcl with bootstrap layer outputs${NC}"
  exit 1
fi

#######################################
# Check Prerequisites
#######################################
echo -e "${YELLOW}🔐 Checking prerequisites...${NC}"

# Check if Terraform is installed
if ! command -v terraform &>/dev/null; then
  echo -e "${RED}❌ Error: Terraform is not installed${NC}"
  exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws &>/dev/null; then
  echo -e "${RED}❌ Error: AWS CLI is not installed${NC}"
  exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &>/dev/null; then
  echo -e "${RED}❌ Error: AWS credentials not configured${NC}"
  exit 1
fi

AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
AWS_USER=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null || echo "unknown")
echo -e "${GREEN}✅ AWS credentials valid${NC}"
echo -e "${BLUE}   Account: ${AWS_ACCOUNT}${NC}"
echo -e "${BLUE}   Identity: ${AWS_USER}${NC}"
echo ""

# Change to terraform directory for all terraform commands
cd "$TERRAFORM_DIR"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🚀 Deploying ${LAYER} Layer${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Environment: ${ENV}${NC}"
echo -e "${BLUE}Layer: ${LAYER}${NC}"
echo -e "${BLUE}Layer Directory: ${LAYER_DIR_NAME}${NC}"
echo -e "${BLUE}Terraform Directory: ${TERRAFORM_DIR}${NC}"
echo -e "${BLUE}Config File: environments/${ENV}/00-config.auto.tfvars${NC}"
echo -e "${BLUE}Backend Config: environments/${ENV}/backend-config.hcl${NC}"
if [[ "$AUTO_APPROVE" == "true" ]]; then
  echo -e "${YELLOW}Auto-approve: enabled${NC}"
fi
if [[ "$SKIP_PLAN" == "true" ]]; then
  echo -e "${YELLOW}Plan: skipped${NC}"
fi
echo ""

#######################################
# Step 1: Initialize Terraform
#######################################
echo -e "${YELLOW}📦 Step 1: Initializing Terraform...${NC}"

if terraform init -backend-config="${BACKEND_CONFIG}" > /dev/null 2>&1; then
  echo -e "${GREEN}✅ Terraform initialized${NC}"
else
  echo -e "${RED}❌ Failed to initialize Terraform${NC}"
  echo -e "${YELLOW}   Running init with verbose output...${NC}"
  terraform init -backend-config="${BACKEND_CONFIG}"
  exit 1
fi
echo ""

#######################################
# Step 2: Validate Configuration
#######################################
echo -e "${YELLOW}✅ Step 2: Validating Terraform configuration...${NC}"

if terraform validate; then
  echo -e "${GREEN}✅ Configuration is valid${NC}"
else
  echo -e "${RED}❌ Configuration validation failed${NC}"
  exit 1
fi
echo ""

#######################################
# Step 3: Plan Changes
#######################################
if [[ "$SKIP_PLAN" == "false" ]]; then
  echo -e "${YELLOW}📋 Step 3: Planning deployment...${NC}"
  
  PLAN_FILE="tfplan-${ENV}"
  
  # Build extra var arguments from TF_VAR_* environment variables
  # Filter out ACR variables for infrastructure layer (they're only for compute layer)
  EXTRA_VAR_ARGS=()
  while IFS='=' read -r name value; do
    if [[ "$name" == TF_VAR_* ]]; then
      var_name="${name#TF_VAR_}"
      # Skip ACR variables for infrastructure layer
      if [[ "$LAYER" == "infrastructure" ]] && [[ "$var_name" == acr_* ]]; then
        continue
      fi
      EXTRA_VAR_ARGS+=("-var=${var_name}=${value}")
    fi
  done < <(env)
  
  # Build terraform plan command
  PLAN_CMD=(
    terraform plan
    -var-file="../../common.auto.tfvars"
    -var-file="environments/${ENV}/00-config.auto.tfvars"
  )
  
  # Add extra vars if any
  if [ ${#EXTRA_VAR_ARGS[@]} -gt 0 ]; then
    PLAN_CMD+=("${EXTRA_VAR_ARGS[@]}")
  fi
  
  PLAN_CMD+=(-out="${PLAN_FILE}")
  
  if "${PLAN_CMD[@]}"; then
    echo -e "${GREEN}✅ Plan created successfully${NC}"
  else
    echo -e "${RED}❌ Plan failed${NC}"
    exit 1
  fi
  echo ""
  
  if [[ "$AUTO_APPROVE" == "false" ]]; then
    echo -e "${YELLOW}⚠️  Review the plan above.${NC}"
    echo -e "${YELLOW}   Press Enter to continue with apply, or Ctrl+C to cancel...${NC}"
    read -r
  fi
else
  echo -e "${YELLOW}⏭️  Step 3: Skipping plan (--skip-plan)${NC}"
  PLAN_FILE=""
  echo ""
fi

#######################################
# Step 3.5: Restore Scheduled Secrets and Cancel Pending KMS Key Deletions
#######################################
# This step restores any secrets scheduled for deletion and cancels any KMS keys
# in "PendingDeletion" state. This allows Terraform to reuse existing resources
# instead of trying to create new ones after an overnight teardown/recreate cycle
echo -e "${YELLOW}🔑 Step 3.5: Restoring scheduled secrets and checking for pending KMS key deletions...${NC}"
if [ -f "${SCRIPT_DIR}/restore-scheduled-secrets.sh" ]; then
  echo -e "${BLUE}   Checking for secrets scheduled for deletion...${NC}"
  "${SCRIPT_DIR}/restore-scheduled-secrets.sh" || true
else
  echo -e "${YELLOW}   Skipping secret restoration (script not found)${NC}"
fi
if [ -f "${SCRIPT_DIR}/cancel-pending-kms-deletions.sh" ]; then
  echo -e "${BLUE}   Checking for pending KMS key deletions...${NC}"
  "${SCRIPT_DIR}/cancel-pending-kms-deletions.sh" || true
else
  echo -e "${YELLOW}   Skipping KMS key cancellation (script not found)${NC}"
fi
echo ""

#######################################
# Step 4: Apply Changes
#######################################
echo -e "${YELLOW}🚀 Step 4: Applying changes...${NC}"

if [[ -n "$PLAN_FILE" && -f "$PLAN_FILE" ]]; then
  # Apply using plan file
  if terraform apply "${PLAN_FILE}"; then
    echo -e "${GREEN}✅ Apply completed successfully${NC}"
    rm -f "${PLAN_FILE}"
  else
    echo -e "${RED}❌ Apply failed${NC}"
    exit 1
  fi
else
  # Apply directly (when --skip-plan is used)
  APPLY_ARGS=()
  if [[ "$AUTO_APPROVE" == "true" ]]; then
    APPLY_ARGS+=("-auto-approve")
  fi
  
  # Build extra var arguments from TF_VAR_* environment variables
  # Filter out ACR variables for infrastructure layer (they're only for compute layer)
  EXTRA_VAR_ARGS=()
  while IFS='=' read -r name value; do
    if [[ "$name" == TF_VAR_* ]]; then
      var_name="${name#TF_VAR_}"
      # Skip ACR variables for infrastructure layer
      if [[ "$LAYER" == "infrastructure" ]] && [[ "$var_name" == acr_* ]]; then
        continue
      fi
      EXTRA_VAR_ARGS+=("-var=${var_name}=${value}")
    fi
  done < <(env)
  
  # Build terraform apply command
  APPLY_CMD=(
    terraform apply
    -var-file="../../common.auto.tfvars"
    -var-file="environments/${ENV}/00-config.auto.tfvars"
  )
  
  # Add extra vars if any
  if [ ${#EXTRA_VAR_ARGS[@]} -gt 0 ]; then
    APPLY_CMD+=("${EXTRA_VAR_ARGS[@]}")
  fi
  
  APPLY_CMD+=("${APPLY_ARGS[@]}")
  
  if "${APPLY_CMD[@]}"; then
    echo -e "${GREEN}✅ Apply completed successfully${NC}"
  else
    echo -e "${RED}❌ Apply failed${NC}"
    exit 1
  fi
fi
echo ""


#######################################
# Step 5: Display Outputs
#######################################
echo -e "${YELLOW}📊 Step 5: Retrieving outputs...${NC}"

if terraform output > /dev/null 2>&1; then
  echo -e "${GREEN}✅ Outputs:${NC}"
  terraform output
else
  echo -e "${YELLOW}ℹ️  No outputs defined${NC}"
fi
echo ""

#######################################
# Summary
#######################################
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Deployment Complete!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}📝 Next Steps:${NC}"
echo -e "   - Review the outputs above"
echo -e "   - Verify resources in AWS Console"
echo -e "   - Proceed with next layer deployment"
echo ""

