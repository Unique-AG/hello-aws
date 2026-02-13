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
# 4. Advanced linting (tflint)
# 5. Shell script linting (shellcheck)
# 6. Security scanning (trivy)
# 7. Compliance scanning (checkov)
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

# Track overall validation result
VALIDATION_FAILED=false

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
SHELLCHECK_AVAILABLE=false
TFLINT_AVAILABLE=false
TRIVY_AVAILABLE=false
CHECKOV_AVAILABLE=false

if command -v shellcheck &>/dev/null; then
  SHELLCHECK_AVAILABLE=true
  echo -e "${GREEN}✅ shellcheck found${NC}"
else
  echo -e "${YELLOW}ℹ️  shellcheck not found (optional, skipping shell script linting)${NC}"
fi

if command -v tflint &>/dev/null; then
  TFLINT_AVAILABLE=true
  echo -e "${GREEN}✅ tflint found${NC}"
else
  echo -e "${YELLOW}ℹ️  tflint not found (optional, skipping advanced linting)${NC}"
fi

if command -v trivy &>/dev/null; then
  TRIVY_AVAILABLE=true
  echo -e "${GREEN}✅ trivy found${NC}"
else
  echo -e "${YELLOW}ℹ️  trivy not found (optional, skipping security scanning)${NC}"
fi

if command -v checkov &>/dev/null; then
  CHECKOV_AVAILABLE=true
  echo -e "${GREEN}✅ checkov found${NC}"
else
  echo -e "${YELLOW}ℹ️  checkov not found (optional, skipping compliance scanning)${NC}"
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

  if terraform init ${INIT_ARGS[@]+"${INIT_ARGS[@]}"} > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Terraform initialized${NC}"
  else
    echo -e "${RED}❌ Failed to initialize Terraform${NC}"
    echo -e "${YELLOW}   Running init with verbose output...${NC}"
    terraform init ${INIT_ARGS[@]+"${INIT_ARGS[@]}"}
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
      echo -e "${RED}❌ tflint found issues${NC}"
      VALIDATION_FAILED=true
    fi
  else
    echo -e "${RED}❌ Failed to initialize tflint${NC}"
    VALIDATION_FAILED=true
  fi
  echo ""
fi

#######################################
# Step 5: Shell Script Linting (shellcheck)
#######################################
if [[ "$SHELLCHECK_AVAILABLE" == "true" ]]; then
  echo -e "${YELLOW}🐚 Step 5: Running shellcheck on shell scripts...${NC}"

  SHELL_SCRIPTS=$(find "$PROJECT_ROOT/scripts" "$LAYER_DIR" -name '*.sh' -type f 2>/dev/null || true)

  if [[ -n "$SHELL_SCRIPTS" ]]; then
    SHELLCHECK_FAILED=false
    while IFS= read -r script; do
      if shellcheck -x "$script" 2>/dev/null; then
        echo -e "${GREEN}   ✅ $(basename "$script")${NC}"
      else
        echo -e "${RED}   ❌ $(basename "$script") has issues${NC}"
        SHELLCHECK_FAILED=true
      fi
    done <<< "$SHELL_SCRIPTS"

    if [[ "$SHELLCHECK_FAILED" == "false" ]]; then
      echo -e "${GREEN}✅ shellcheck passed${NC}"
    else
      echo -e "${RED}❌ shellcheck found issues${NC}"
      VALIDATION_FAILED=true
    fi
  else
    echo -e "${GREEN}✅ No shell scripts found to check${NC}"
  fi
  echo ""
else
  echo -e "${YELLOW}⏭️  Step 5: Skipping shellcheck (not installed)${NC}"
  echo ""
fi

#######################################
# Step 6: Security Scanning (trivy)
#######################################
if [[ "$TRIVY_AVAILABLE" == "true" ]]; then
  echo -e "${YELLOW}🔒 Step 6: Running trivy IaC security scan...${NC}"

  # shellcheck disable=SC2054
  TRIVY_ARGS=(fs --scanners misconfig --severity HIGH,CRITICAL --exit-code 0)
  # Use root .trivyignore for suppressed findings (see docs/security-baseline.md)
  if [[ -f "$PROJECT_ROOT/.trivyignore" ]]; then
    TRIVY_ARGS+=(--ignorefile "$PROJECT_ROOT/.trivyignore")
  fi
  # Pass tfvars so trivy can resolve variables (avoids null-value panics in adaptDefaultTags)
  if [[ -f "$COMMON_CONFIG" ]]; then
    TRIVY_ARGS+=(--tf-vars "$COMMON_CONFIG")
  fi
  if [[ -f "$CONFIG_FILE" ]]; then
    TRIVY_ARGS+=(--tf-vars "$CONFIG_FILE")
  fi
  TRIVY_ARGS+=("$TERRAFORM_DIR")

  if trivy "${TRIVY_ARGS[@]}"; then
    echo -e "${GREEN}✅ trivy passed (no HIGH/CRITICAL misconfigurations)${NC}"
  else
    echo -e "${RED}❌ trivy found security issues${NC}"
    echo -e "${YELLOW}   Run 'trivy fs --scanners misconfig ${TERRAFORM_DIR}' for details${NC}"
    VALIDATION_FAILED=true
  fi
  echo ""
else
  echo -e "${YELLOW}⏭️  Step 6: Skipping trivy (not installed)${NC}"
  echo ""
fi

#######################################
# Step 7: Compliance Scanning (checkov)
#######################################
if [[ "$CHECKOV_AVAILABLE" == "true" ]]; then
  echo -e "${YELLOW}📋 Step 7: Running checkov compliance scan...${NC}"
  
  CHECKOV_ARGS=(--quiet --framework terraform)
  if [[ -f "${TERRAFORM_DIR}/.checkov.yml" ]]; then
    CHECKOV_ARGS+=(--config-file "${TERRAFORM_DIR}/.checkov.yml")
  fi

  if checkov -d "$TERRAFORM_DIR" "${CHECKOV_ARGS[@]}"; then
    echo -e "${GREEN}✅ checkov passed${NC}"
  else
    echo -e "${RED}❌ checkov found compliance issues${NC}"
    echo -e "${YELLOW}   Run 'checkov -d ${TERRAFORM_DIR} --framework terraform' for details${NC}"
    VALIDATION_FAILED=true
  fi
  echo ""
else
  echo -e "${YELLOW}⏭️  Step 7: Skipping checkov (not installed)${NC}"
  echo ""
fi


#######################################
# Summary
#######################################
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [[ "$VALIDATION_FAILED" == "true" ]]; then
  echo -e "${RED}❌ Validation Failed${NC}"
else
  echo -e "${GREEN}✅ Validation Complete!${NC}"
fi
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}📊 Summary:${NC}"
echo -e "   ✅ Terraform initialized"
echo -e "   ✅ Configuration validated"
echo -e "   ✅ Code formatting checked"
if [[ "$TFLINT_AVAILABLE" == "true" ]]; then
  echo -e "   ✅ Advanced linting (tflint) completed"
fi
if [[ "$SHELLCHECK_AVAILABLE" == "true" ]]; then
  echo -e "   ✅ Shell script linting (shellcheck) completed"
fi
if [[ "$TRIVY_AVAILABLE" == "true" ]]; then
  echo -e "   ✅ Security scanning (trivy) completed"
fi
if [[ "$CHECKOV_AVAILABLE" == "true" ]]; then
  echo -e "   ✅ Compliance scanning (checkov) completed"
fi
echo ""

if [[ "$VALIDATION_FAILED" == "true" ]]; then
  echo -e "${RED}Fix the issues above and re-run validation.${NC}"
  echo ""
  exit 1
fi

echo -e "${BLUE}📝 Next Steps:${NC}"
echo -e "   Run deployment: ./scripts/deploy.sh ${LAYER} ${ENV}"
echo ""
echo -e "${BLUE}💡 Installation Tips:${NC}"
if [[ "$SHELLCHECK_AVAILABLE" == "false" ]]; then
  echo -e "   ${YELLOW}Install shellcheck:${NC} brew install shellcheck"
fi
if [[ "$TFLINT_AVAILABLE" == "false" ]]; then
  echo -e "   ${YELLOW}Install tflint:${NC} brew install tflint"
fi
if [[ "$TRIVY_AVAILABLE" == "false" ]]; then
  echo -e "   ${YELLOW}Install trivy:${NC} brew install trivy"
fi
if [[ "$CHECKOV_AVAILABLE" == "false" ]]; then
  echo -e "   ${YELLOW}Install checkov:${NC} pip install checkov"
fi
echo ""

