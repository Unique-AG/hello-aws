#!/bin/bash
set -euo pipefail

#######################################
# Terraform Destroy Script
#######################################
#
# This script destroys Terraform configuration by:
# 1. Initializing Terraform
# 2. Validating configuration
# 3. Planning destruction
# 4. Destroying resources
#
# Usage:
#   ./scripts/destroy.sh [layer] [environment] [--auto-approve] [--skip-plan]
#
# Examples:
#   ./scripts/destroy.sh governance sbx
#   ./scripts/destroy.sh governance dev --auto-approve
#   ./scripts/destroy.sh infrastructure prod --skip-plan --auto-approve
#   ./scripts/destroy.sh bootstrap sbx
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
      shift
      ;;
    --skip-plan)
      SKIP_PLAN=true
      shift
      ;;
  esac
done

# Validate arguments
if [[ -z "$LAYER" ]]; then
  echo -e "${RED}❌ Error: Layer is required${NC}"
  echo -e "${YELLOW}   Usage: ./scripts/destroy.sh [layer] [environment] [--auto-approve] [--skip-plan]${NC}"
  echo -e "${YELLOW}   Examples:${NC}"
  echo -e "${YELLOW}     ./scripts/destroy.sh bootstrap sbx${NC}"
  echo -e "${YELLOW}     ./scripts/destroy.sh governance dev --auto-approve${NC}"
  echo -e "${YELLOW}     ./scripts/destroy.sh infrastructure prod --skip-plan --auto-approve${NC}"
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
echo -e "${RED}🗑️  Destroying ${LAYER} Layer${NC}"
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
# Step 3: Plan Destruction
#######################################
if [[ "$SKIP_PLAN" == "false" ]]; then
  echo -e "${YELLOW}📋 Step 3: Planning destruction...${NC}"
  
  PLAN_FILE="tfplan-destroy-${ENV}"
  
  if terraform plan \
    -destroy \
    -var-file="../../common.auto.tfvars" \
    -var-file="environments/${ENV}/00-config.auto.tfvars" \
    -out="${PLAN_FILE}"; then
    echo -e "${GREEN}✅ Destroy plan created successfully${NC}"
  else
    echo -e "${RED}❌ Destroy plan failed${NC}"
    exit 1
  fi
  echo ""
  
  if [[ "$AUTO_APPROVE" == "false" ]]; then
    echo -e "${RED}⚠️  WARNING: This will destroy all resources in the ${LAYER} layer for ${ENV} environment!${NC}"
    echo -e "${YELLOW}   Review the plan above carefully.${NC}"
    echo -e "${YELLOW}   Press Enter to continue with destroy, or Ctrl+C to cancel...${NC}"
    read -r
  fi
else
  echo -e "${YELLOW}⏭️  Step 3: Skipping plan (--skip-plan)${NC}"
  PLAN_FILE=""
  echo ""
  
  if [[ "$AUTO_APPROVE" == "false" ]]; then
    echo -e "${RED}⚠️  WARNING: This will destroy all resources in the ${LAYER} layer for ${ENV} environment!${NC}"
    echo -e "${YELLOW}   Press Enter to continue with destroy, or Ctrl+C to cancel...${NC}"
    read -r
  fi
fi

#######################################
# Step 4: Destroy Resources
#######################################
echo -e "${RED}🗑️  Step 4: Destroying resources...${NC}"

if [[ -n "$PLAN_FILE" && -f "$PLAN_FILE" ]]; then
  # Destroy using plan file
  if terraform apply "${PLAN_FILE}"; then
    echo -e "${GREEN}✅ Destroy completed successfully${NC}"
    rm -f "${PLAN_FILE}"
  else
    echo -e "${RED}❌ Destroy failed${NC}"
    exit 1
  fi
else
  # Destroy directly (when --skip-plan is used)
  DESTROY_ARGS=()
  if [[ "$AUTO_APPROVE" == "true" ]]; then
    DESTROY_ARGS+=("-auto-approve")
  fi
  
  if terraform destroy \
    -var-file="../../common.auto.tfvars" \
    -var-file="environments/${ENV}/00-config.auto.tfvars" \
    "${DESTROY_ARGS[@]}"; then
    echo -e "${GREEN}✅ Destroy completed successfully${NC}"
  else
    echo -e "${RED}❌ Destroy failed${NC}"
    exit 1
  fi
fi
echo ""

#######################################
# Step 5: Display Final State
#######################################
echo -e "${YELLOW}📊 Step 5: Checking final state...${NC}"

if terraform state list > /dev/null 2>&1; then
  STATE_COUNT=$(terraform state list | wc -l | tr -d ' ')
  if [[ $STATE_COUNT -eq 0 ]]; then
    echo -e "${GREEN}✅ All resources destroyed - state is empty${NC}"
  else
    echo -e "${YELLOW}⚠️  Warning: ${STATE_COUNT} resource(s) still in state${NC}"
    echo -e "${YELLOW}   Run 'terraform state list' to see remaining resources${NC}"
  fi
else
  echo -e "${BLUE}ℹ️  State file not accessible or empty${NC}"
fi
echo ""

#######################################
# Summary
#######################################
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Destruction Complete!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}📝 Notes:${NC}"
echo -e "   - KMS keys are scheduled for deletion (7-day minimum window)"
echo -e "   - To reuse KMS keys after teardown, run:"
echo -e "     ./scripts/cancel-pending-kms-deletions"
echo -e "   - State file remains in S3 backend"
echo -e "   - To completely remove state, delete from S3 manually"
echo ""

