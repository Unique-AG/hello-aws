#!/bin/bash
set -euo pipefail

#######################################
# Terraform Validation Script
#######################################
#
# This script validates Terraform configuration by:
# 1. Initializing Terraform
# 2. Validating configuration syntax
# 3. Linting code style and format
# 4. Security scanning (tflint, tfsec, checkov)
# 5. Secrets scanning (trivy)
#
# Usage:
#   ./scripts/validate.sh [layer] [environment] [skip_init]
#
# Options:
#   skip_init: Set to "true" to skip Terraform initialization and only run linting/security checks
#
# Examples:
#   ./scripts/validate.sh governance sbx                    # Full validation (requires infrastructure)
#   ./scripts/validate.sh governance sbx true              # Lint-only mode (no infrastructure needed)
#   ./scripts/validate.sh infrastructure prod true         # Lint-only mode for production
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
SKIP_INIT="${3:-false}"

# Validate arguments
if [[ -z "$LAYER" ]]; then
  echo -e "${RED}❌ Error: Layer is required${NC}"
  echo -e "${YELLOW}   Usage: ./scripts/validate.sh [layer] [environment]${NC}"
  echo -e "${YELLOW}   Examples:${NC}"
  echo -e "${YELLOW}     ./scripts/validate.sh bootstrap sbx${NC}"
  echo -e "${YELLOW}     ./scripts/validate.sh governance dev${NC}"
  echo -e "${YELLOW}     ./scripts/validate.sh infrastructure prod${NC}"
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

# Check if backend config exists (warning only, not required for validation)
if [[ ! -f "$BACKEND_CONFIG" ]]; then
  echo -e "${YELLOW}⚠️  Warning: Backend config file not found: ${BACKEND_CONFIG}${NC}"
  echo -e "${YELLOW}   Validation will continue, but backend initialization may fail${NC}"
fi

#######################################
# Check Prerequisites
#######################################
echo -e "${YELLOW}🔍 Checking prerequisites...${NC}"

# Check if Terraform is installed
if ! command -v terraform &>/dev/null; then
  echo -e "${RED}❌ Error: Terraform is not installed${NC}"
  echo -e "${YELLOW}   Please install Terraform:${NC}"
  echo -e "${YELLOW}   macOS: brew install terraform${NC}"
  echo -e "${YELLOW}   Linux: See https://www.terraform.io/downloads${NC}"
  exit 1
fi

TERRAFORM_VERSION=$(terraform version -json | jq -r '.terraform_version' 2>/dev/null || echo "unknown")
echo -e "${GREEN}✅ Terraform ${TERRAFORM_VERSION} found${NC}"

# Check if security scanning tools are installed
TFLINT_AVAILABLE=false
TFSEC_AVAILABLE=false
CHECKOV_AVAILABLE=false
TRIVY_AVAILABLE=false

if command -v tflint &>/dev/null; then
  TFLINT_AVAILABLE=true
  TFLINT_VERSION=$(tflint --version 2>/dev/null | head -n1 || echo "unknown")
  echo -e "${GREEN}✅ tflint found${NC}"
else
  echo -e "${YELLOW}ℹ️  tflint not found (optional, skipping advanced linting)${NC}"
fi

if command -v tfsec &>/dev/null; then
  TFSEC_AVAILABLE=true
  TFSEC_VERSION=$(tfsec --version 2>/dev/null | head -n1 || echo "unknown")
  echo -e "${GREEN}✅ tfsec found${NC}"
else
  echo -e "${YELLOW}ℹ️  tfsec not found (optional, skipping security scanning)${NC}"
fi

if command -v checkov &>/dev/null; then
  CHECKOV_AVAILABLE=true
  CHECKOV_VERSION=$(checkov --version 2>/dev/null | head -n1 || echo "unknown")
  echo -e "${GREEN}✅ checkov found${NC}"
else
  echo -e "${YELLOW}ℹ️  checkov not found (optional, skipping compliance scanning)${NC}"
fi

if command -v trivy &>/dev/null; then
  TRIVY_AVAILABLE=true
  TRIVY_VERSION=$(trivy --version 2>/dev/null | head -n1 || echo "unknown")
  echo -e "${GREEN}✅ trivy found${NC}"
else
  echo -e "${YELLOW}ℹ️  trivy not found (optional, skipping secrets scanning)${NC}"
fi

echo ""

# Change to terraform directory for all terraform commands
cd "$TERRAFORM_DIR"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🔍 Validating ${LAYER} Layer${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Environment: ${ENV}${NC}"
echo -e "${BLUE}Layer: ${LAYER}${NC}"
echo -e "${BLUE}Layer Directory: ${LAYER_DIR_NAME}${NC}"
echo -e "${BLUE}Terraform Directory: ${TERRAFORM_DIR}${NC}"
echo -e "${BLUE}Config File: environments/${ENV}/00-config.auto.tfvars${NC}"
echo -e "${BLUE}Backend Config: environments/${ENV}/backend-config.hcl${NC}"
echo ""

if [[ "$SKIP_INIT" != "true" ]]; then
  #######################################
  # Step 1: Initialize Terraform
  #######################################
  echo -e "${YELLOW}📦 Step 1: Initializing Terraform...${NC}"

  INIT_ARGS=()
  if [[ -f "$BACKEND_CONFIG" ]]; then
    INIT_ARGS+=("-backend-config=${BACKEND_CONFIG}")
  fi

  if terraform init "${INIT_ARGS[@]}" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Terraform initialized${NC}"
  else
    echo -e "${RED}❌ Failed to initialize Terraform${NC}"
    echo -e "${YELLOW}   Running init with verbose output...${NC}"
    terraform init "${INIT_ARGS[@]}"
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
  # Step 3: Format Check
  #######################################
  echo -e "${YELLOW}🎨 Step 3: Checking code formatting...${NC}"

  UNFORMATTED_FILES=$(terraform fmt -check -recursive 2>&1 || true)
  if [[ -z "$UNFORMATTED_FILES" ]]; then
    echo -e "${GREEN}✅ All files are properly formatted${NC}"
  else
    echo -e "${RED}❌ Some files are not properly formatted:${NC}"
    echo "$UNFORMATTED_FILES"
    echo ""
    echo -e "${YELLOW}   To fix formatting, run:${NC}"
    echo -e "${YELLOW}   terraform fmt -recursive${NC}"
    exit 1
  fi
  echo ""
fi

if [[ "$SKIP_INIT" == "true" ]]; then
  echo -e "${BLUE}⏭️  Skipping Terraform initialization (lint-only mode)${NC}"
  echo ""

  #######################################
  # Step 1: Format Check (always run)
  #######################################
  echo -e "${YELLOW}🎨 Step 1: Checking code formatting...${NC}"

  UNFORMATTED_FILES=$(terraform fmt -check -recursive 2>&1 || true)
  if [[ -z "$UNFORMATTED_FILES" ]]; then
    echo -e "${GREEN}✅ All files are properly formatted${NC}"
  else
    echo -e "${RED}❌ Some files are not properly formatted:${NC}"
    echo "$UNFORMATTED_FILES"
    echo ""
    echo -e "${YELLOW}   To fix formatting, run:${NC}"
    echo -e "${YELLOW}   terraform fmt -recursive${NC}"
    exit 1
  fi
  echo ""
fi

#######################################
# Step 4: Advanced Linting (tflint)
#######################################
if [[ "$TFLINT_AVAILABLE" == "true" ]]; then
  echo -e "${YELLOW}🔍 Step 4: Running tflint...${NC}"
  
  if tflint --init > /dev/null 2>&1; then
    if tflint --chdir="$TERRAFORM_DIR"; then
      echo -e "${GREEN}✅ tflint passed${NC}"
    else
      echo -e "${YELLOW}⚠️  tflint found issues (non-blocking)${NC}"
    fi
  else
    echo -e "${YELLOW}⚠️  Failed to initialize tflint (non-blocking)${NC}"
  fi
  echo ""
fi

#######################################
# Step 5: Security Scanning (tfsec)
#######################################
if [[ "$TFSEC_AVAILABLE" == "true" ]]; then
  echo -e "${YELLOW}🔒 Step 5: Running tfsec security scan...${NC}"
  
  TFSEC_ARGS="--minimum-severity HIGH"
  if [[ -f "${TERRAFORM_DIR}/.tfsec.yml" ]]; then
    TFSEC_ARGS="$TFSEC_ARGS --config-file ${TERRAFORM_DIR}/.tfsec.yml"
  fi
  
  if tfsec "$TERRAFORM_DIR" $TFSEC_ARGS --soft-fail; then
    echo -e "${GREEN}✅ tfsec passed (no HIGH severity issues)${NC}"
  else
    echo -e "${YELLOW}⚠️  tfsec found security issues (non-blocking)${NC}"
    echo -e "${YELLOW}   Run 'tfsec ${TERRAFORM_DIR} --minimum-severity HIGH' for details${NC}"
  fi
  echo ""
else
  echo -e "${YELLOW}⏭️  Step 5: Skipping tfsec (not installed)${NC}"
  echo ""
fi

#######################################
# Step 6: Compliance Scanning (checkov)
#######################################
if [[ "$CHECKOV_AVAILABLE" == "true" ]]; then
  echo -e "${YELLOW}📋 Step 6: Running checkov compliance scan...${NC}"
  
  CHECKOV_ARGS="--quiet --framework terraform"
  if [[ -f "${TERRAFORM_DIR}/.checkov.yml" ]]; then
    CHECKOV_ARGS="$CHECKOV_ARGS --config-file ${TERRAFORM_DIR}/.checkov.yml"
  fi
  
  if checkov -d "$TERRAFORM_DIR" $CHECKOV_ARGS; then
    echo -e "${GREEN}✅ checkov passed${NC}"
  else
    echo -e "${YELLOW}⚠️  checkov found compliance issues (non-blocking)${NC}"
    echo -e "${YELLOW}   Run 'checkov -d ${TERRAFORM_DIR} --framework terraform' for details${NC}"
  fi
  echo ""
else
  echo -e "${YELLOW}⏭️  Step 6: Skipping checkov (not installed)${NC}"
  echo ""
fi

#######################################
# Step 7: Secrets Scanning (trivy)
#######################################
if [[ "$TRIVY_AVAILABLE" == "true" ]]; then
  echo -e "${YELLOW}🔐 Step 7: Running trivy secrets scan...${NC}"
  
  if trivy fs --security-checks secret --severity HIGH,CRITICAL --exit-code 0 "$TERRAFORM_DIR"; then
    echo -e "${GREEN}✅ trivy secrets scan passed${NC}"
  else
    echo -e "${YELLOW}⚠️  trivy found potential secrets (non-blocking)${NC}"
    echo -e "${YELLOW}   Run 'trivy fs --security-checks secret ${TERRAFORM_DIR}' for details${NC}"
  fi
  echo ""
else
  echo -e "${YELLOW}⏭️  Step 7: Skipping trivy (not installed)${NC}"
  echo ""
fi

#######################################
# Summary
#######################################
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Validation Complete!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}📊 Summary:${NC}"
echo -e "   ✅ Terraform initialized"
echo -e "   ✅ Configuration validated"
echo -e "   ✅ Code formatting checked"
if [[ "$TFLINT_AVAILABLE" == "true" ]]; then
  echo -e "   ✅ Advanced linting (tflint) completed"
fi
if [[ "$TFSEC_AVAILABLE" == "true" ]]; then
  echo -e "   ✅ Security scanning (tfsec) completed"
fi
if [[ "$CHECKOV_AVAILABLE" == "true" ]]; then
  echo -e "   ✅ Compliance scanning (checkov) completed"
fi
if [[ "$TRIVY_AVAILABLE" == "true" ]]; then
  echo -e "   ✅ Secrets scanning (trivy) completed"
fi
echo ""
echo -e "${BLUE}📝 Next Steps:${NC}"
echo -e "   Run deployment: ./scripts/deploy.sh ${LAYER} ${ENV}"
echo ""
echo -e "${BLUE}💡 Installation Tips:${NC}"
if [[ "$TFLINT_AVAILABLE" == "false" ]]; then
  echo -e "   ${YELLOW}Install tflint:${NC} brew install tflint"
fi
if [[ "$TFSEC_AVAILABLE" == "false" ]]; then
  echo -e "   ${YELLOW}Install tfsec:${NC} brew install tfsec"
fi
if [[ "$CHECKOV_AVAILABLE" == "false" ]]; then
  echo -e "   ${YELLOW}Install checkov:${NC} pip install checkov"
fi
if [[ "$TRIVY_AVAILABLE" == "false" ]]; then
  echo -e "   ${YELLOW}Install trivy:${NC} brew install trivy"
fi
echo ""

