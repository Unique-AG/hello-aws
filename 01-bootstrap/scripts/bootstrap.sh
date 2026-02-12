#!/bin/bash
set -euo pipefail

# Bootstrap Layer Deployment Script
#
# Deploys the bootstrap layer using local backend first, then migrates to S3.
#
# Usage:
#   ./bootstrap.sh [environment] [--skip-plan] [--auto-approve] [--connect-only]
#
# Environments: prod, stag, dev, sbx

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/01-bootstrap/terraform"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ENV=""
SKIP_PLAN=false
AUTO_APPROVE=false
CONNECT_ONLY=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-plan)
      SKIP_PLAN=true
      shift
      ;;
    --auto-approve)
      AUTO_APPROVE=true
      shift
      ;;
    --connect-only)
      CONNECT_ONLY=true
      SKIP_PLAN=true  # Connecting to existing state means we don't want to plan/apply
      shift
      ;;
    -*)
      echo -e "${RED}Error: Unknown option: $1${NC}"
      exit 1
      ;;
    *)
      if [[ -z "$ENV" ]]; then
        ENV="$1"
      else
        echo -e "${RED}Error: Multiple environments specified${NC}"
        exit 1
      fi
      shift
      ;;
  esac
done

ENV="${ENV:-dev}"

if [[ ! "$ENV" =~ ^(prod|stag|dev|sbx)$ ]]; then
  echo -e "${RED}Error: Environment must be one of: prod, stag, dev, sbx${NC}"
  exit 1
fi

CONFIG_FILE="${TERRAFORM_DIR}/environments/${ENV}/00-config.auto.tfvars"
COMMON_CONFIG="${PROJECT_ROOT}/common.auto.tfvars"
COMMON_TEMPLATE="${PROJECT_ROOT}/common.auto.tfvars.template"

if [[ ! -d "$TERRAFORM_DIR" ]]; then
  echo -e "${RED}Error: Terraform directory not found: ${TERRAFORM_DIR}${NC}"
  exit 1
fi

if [[ ! -f "$COMMON_CONFIG" ]]; then
  echo -e "${RED}Error: common.auto.tfvars not found${NC}"
  echo -e "${YELLOW}   This file must be created manually from the template.${NC}"
  echo ""
  if [[ -f "$COMMON_TEMPLATE" ]]; then
    echo -e "${BLUE}   Template file found: ${COMMON_TEMPLATE}${NC}"
    echo -e "${YELLOW}   To create common.auto.tfvars:${NC}"
    echo -e "${YELLOW}     1. Copy the template:${NC}"
    echo -e "${BLUE}        cp ${COMMON_TEMPLATE} ${COMMON_CONFIG}${NC}"
    echo -e "${YELLOW}     2. Edit ${COMMON_CONFIG} and update the values:${NC}"
    echo -e "${BLUE}        - aws_region${NC}"
    echo -e "${BLUE}        - org and org_moniker${NC}"
    echo -e "${BLUE}        - product and product_moniker${NC}"
    echo -e "${BLUE}        - semantic_version (if needed)${NC}"
  else
    echo -e "${RED}   Template file not found: ${COMMON_TEMPLATE}${NC}"
  fi
  echo ""
  exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo -e "${RED}Error: Config file not found: ${CONFIG_FILE}${NC}"
  exit 1
fi

echo -e "${YELLOW}Checking AWS credentials...${NC}"

if ! command -v aws &>/dev/null; then
  echo -e "${RED}Error: AWS CLI is not installed${NC}"
  echo -e "${YELLOW}   Please install AWS CLI:${NC}"
  echo -e "${YELLOW}   macOS: brew install awscli${NC}"
  echo -e "${YELLOW}   Linux: See https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html${NC}"
  exit 1
fi

if ! aws sts get-caller-identity &>/dev/null; then
  echo -e "${RED}Error: AWS credentials not configured${NC}"
  echo -e "${YELLOW}   Please configure AWS credentials using one of:${NC}"
  echo -e "${YELLOW}   1. AWS SSO: aws sso login --profile <profile-name>${NC}"
  echo -e "${YELLOW}   2. AWS CLI: aws configure${NC}"
  echo -e "${YELLOW}   ${NC}"
  echo -e "${YELLOW}   Verify credentials:${NC}"
  echo -e "${YELLOW}   - Test: aws sts get-caller-identity${NC}"
  exit 1
fi

AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
AWS_USER=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null || echo "unknown")
echo -e "${GREEN}AWS credentials valid${NC}"
echo -e "${BLUE}   Account: ${AWS_ACCOUNT}${NC}"
echo -e "${BLUE}   Identity: ${AWS_USER}${NC}"
echo ""

cd "$TERRAFORM_DIR"

aws_region=$(grep "^aws_region.*=" "${PROJECT_ROOT}/common.auto.tfvars" | cut -d'"' -f2)
org_moniker=$(grep "^org_moniker.*=" "${PROJECT_ROOT}/common.auto.tfvars" | cut -d'"' -f2)
product_moniker=$(grep "^product_moniker[[:space:]]*=" "${PROJECT_ROOT}/common.auto.tfvars" | cut -d'"' -f2)

if [[ -z "$aws_region" ]] || [[ -z "$org_moniker" ]] || [[ -z "$product_moniker" ]]; then
  echo -e "${RED}Error: Failed to extract required values from common.auto.tfvars${NC}"
  echo -e "${RED}   aws_region: ${aws_region:-NOT FOUND}${NC}"
  echo -e "${RED}   org_moniker: ${org_moniker:-NOT FOUND}${NC}"
  echo -e "${RED}   product_moniker: ${product_moniker:-NOT FOUND}${NC}"
  exit 1
fi

region_to_short() {
  case "$1" in
    eu-central-1)    echo "euc1" ;;
    eu-central-2)    echo "euc2" ;;
    eu-west-1)       echo "euw1" ;;
    eu-west-2)       echo "euw2" ;;
    eu-west-3)       echo "euw3" ;;
    eu-north-1)      echo "eun1" ;;
    eu-south-1)      echo "eus1" ;;
    us-east-1)       echo "use1" ;;
    us-east-2)       echo "use2" ;;
    us-west-1)       echo "usw1" ;;
    us-west-2)       echo "usw2" ;;
    ap-southeast-1)  echo "apse1" ;;
    ap-southeast-2)  echo "apse2" ;;
    ap-northeast-1)  echo "apne1" ;;
    ap-northeast-2)  echo "apne2" ;;
    ca-central-1)    echo "cac1" ;;
    sa-east-1)       echo "sae1" ;;
    *)
      echo -e "${RED}Error: Unsupported AWS region '${1}' — add a mapping to region_to_short() in this script${NC}" >&2
      exit 1
      ;;
  esac
}
aws_region_short=$(region_to_short "$aws_region")

env_to_short() {
  case "$1" in
    prod) echo "p" ;;
    stag) echo "s" ;;
    dev)  echo "d" ;;
    sbx)  echo "x" ;;
  esac
}

generate_backend_config_from_template() {
  local TEMPLATE_FILE="$1"
  local OUTPUT_FILE="$2"
  local BUCKET_VALUE="$3"
  local KEY_VALUE="$4"
  local REGION_VALUE="$5"
  local KMS_ALIAS_VALUE="$6"
  local ENV_VALUE="$7"

  if [[ ! -f "$TEMPLATE_FILE" ]]; then
    echo -e "${RED}Template file not found: ${TEMPLATE_FILE}${NC}"
    return 1
  fi

  mkdir -p "$(dirname "$OUTPUT_FILE")"

  sed -e "s|{{BUCKET}}|${BUCKET_VALUE}|g" \
      -e "s|{{KEY}}|${KEY_VALUE}|g" \
      -e "s|{{REGION}}|${REGION_VALUE}|g" \
      -e "s|{{KMS_ALIAS}}|${KMS_ALIAS_VALUE}|g" \
      -e "s|{{ENV}}|${ENV_VALUE}|g" \
      "$TEMPLATE_FILE" > "$OUTPUT_FILE"

  return 0
}

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Deploying Bootstrap Layer${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Environment: ${ENV}${NC}"
echo -e "${BLUE}Terraform Directory: ${TERRAFORM_DIR}${NC}"
echo -e "${BLUE}Config File: environments/${ENV}/00-config.auto.tfvars${NC}"
echo -e "${BLUE}Backend Config: environments/${ENV}/backend-config.hcl${NC}"
echo ""

echo -e "${YELLOW}Step 0: Checking current state location...${NC}"

STATE_IN_S3=false

if [[ "$CONNECT_ONLY" == "true" ]]; then
  STATE_IN_S3=true
  echo -e "${BLUE}Connect-only mode: Assuming state exists in S3${NC}"
fi

if [[ -f "backend.tf" ]]; then
  if [[ -f "environments/${ENV}/backend-config.hcl" ]]; then
    BUCKET_VALUE=$(grep -E '^bucket\s*=' "environments/${ENV}/backend-config.hcl" | awk -F'"' '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || echo "")
    if [[ -n "$BUCKET_VALUE" ]] && [[ "$BUCKET_VALUE" != "" ]]; then
      if terraform init -backend-config="environments/${ENV}/backend-config.hcl" -reconfigure > /dev/null 2>&1; then
        if terraform state list > /dev/null 2>&1; then
          STATE_IN_S3=true
          echo -e "${GREEN}State is already in S3 backend${NC}"
        fi
      fi
    fi
  fi
fi

if [[ "$CONNECT_ONLY" == "true" ]] && [[ "$STATE_IN_S3" == "false" ]]; then
  echo -e "${YELLOW}--connect-only specified but existing state not detected. Will attempt to create backend-config.hcl.${NC}"
  STATE_IN_S3=true  # Force connection mode
elif [[ "$STATE_IN_S3" == "false" ]]; then
  echo -e "${BLUE}State is local or doesn't exist, will migrate to S3 after deployment${NC}"
fi
echo ""

if [[ "$CONNECT_ONLY" == "true" ]] && [[ ! -f "environments/${ENV}/backend-config.hcl" ]]; then
  echo -e "${YELLOW}Creating backend-config.hcl for connect-only mode...${NC}"

  BUCKET_NAME="s3-${org_moniker}-${product_moniker}-$(env_to_short "$ENV")-${aws_region_short}-tfstate"
  KMS_ALIAS="alias/kms-${org_moniker}-${product_moniker}-${ENV}-${aws_region_short}-tfstate"
  REGION="$aws_region"
  STATE_KEY="bootstrap/terraform.tfstate"

  KMS_KEY_ARN=$(aws kms describe-key --key-id "$KMS_ALIAS" --region "$REGION" --query 'KeyMetadata.Arn' --output text 2>/dev/null || echo "$KMS_ALIAS")
  KMS_KEY_ARN_ESCAPED=$(echo "$KMS_KEY_ARN" | sed 's/\//\\\//g')

  echo -e "${BLUE}   Debug: BUCKET_NAME=${BUCKET_NAME}, KMS_KEY_ARN=${KMS_KEY_ARN}${NC}"

  TEMPLATE_FILE="${TERRAFORM_DIR}/backend-config.hcl.template"
  OUTPUT_FILE="${TERRAFORM_DIR}/environments/${ENV}/backend-config.hcl"

  if generate_backend_config_from_template "$TEMPLATE_FILE" "$OUTPUT_FILE" "$BUCKET_NAME" "$STATE_KEY" "$aws_region" "$KMS_KEY_ARN_ESCAPED" "$ENV"; then
    echo -e "${GREEN}Backend configuration created: environments/${ENV}/backend-config.hcl${NC}"
    echo -e "${BLUE}   Bucket: ${BUCKET_NAME}${NC}"
    echo -e "${BLUE}   Key: ${STATE_KEY}${NC}"
    echo -e "${BLUE}   Region: ${aws_region}${NC}"
    echo -e "${BLUE}   KMS Alias: ${KMS_ALIAS}${NC}"
  else
    echo -e "${RED}Failed to create backend configuration${NC}"
    exit 1
  fi
  echo ""
fi

if [[ "$STATE_IN_S3" == "true" ]]; then
  # State is already in S3, use S3 backend directly
  echo -e "${YELLOW}Step 1: Initializing Terraform with S3 backend...${NC}"

  # Ensure backend.tf exists
  if [[ ! -f "backend.tf" ]] && [[ -f "backend.tf.bak" ]]; then
    mv backend.tf.bak backend.tf
    echo -e "${BLUE}   Restored backend.tf${NC}"
  fi

  if terraform init -backend-config="environments/${ENV}/backend-config.hcl" -reconfigure > /dev/null 2>&1; then
    echo -e "${GREEN}Terraform initialized with S3 backend${NC}"
  else
    echo -e "${RED}Failed to initialize Terraform${NC}"
    terraform init -backend-config="environments/${ENV}/backend-config.hcl" -reconfigure
    exit 1
  fi
else
  echo -e "${YELLOW}Step 1: Initializing Terraform with local backend...${NC}"

  if [ -f "backend.tf" ]; then
    mv backend.tf backend.tf.bak
    echo -e "${BLUE}   Temporarily disabled S3 backend for initial deployment${NC}"
  fi

  if terraform init; then
    echo -e "${GREEN}Terraform initialized with local backend${NC}"
  else
    if [ -f "backend.tf.bak" ]; then
      mv backend.tf.bak backend.tf
    fi
    echo -e "${RED}Failed to initialize Terraform${NC}"
    exit 1
  fi
fi
echo ""

if [[ "$STATE_IN_S3" == "true" ]]; then
  echo -e "${YELLOW}Step 2: Skipping plan and apply (connecting to existing remote state)${NC}"
  echo ""
else
  if [[ "$SKIP_PLAN" == "false" ]]; then
    echo -e "${YELLOW}Step 2: Planning deployment...${NC}"
    if terraform plan -var-file="../../common.auto.tfvars" -var-file="environments/${ENV}/00-config.auto.tfvars" -out=tfplan; then
      echo -e "${GREEN}Plan created successfully${NC}"
      echo ""

      if [[ "$AUTO_APPROVE" == "false" ]]; then
        echo -e "${YELLOW}Review the plan above. Press Enter to continue with apply, or Ctrl+C to cancel...${NC}"
        read -r
      fi
    else
      echo -e "${RED}Plan failed${NC}"
      exit 1
    fi
  else
    echo -e "${YELLOW}Step 2: Skipping plan (--skip-plan flag)${NC}"
    echo ""
  fi

  echo -e "${YELLOW}Step 3: Applying configuration...${NC}"
  if [[ "$SKIP_PLAN" == "true" ]]; then
    AUTO_APPROVE_FLAG=""
    [[ "$AUTO_APPROVE" == "true" ]] && AUTO_APPROVE_FLAG="-auto-approve"
    if terraform apply -var-file="../../common.auto.tfvars" -var-file="environments/${ENV}/00-config.auto.tfvars" ${AUTO_APPROVE_FLAG}; then
      echo -e "${GREEN}Configuration applied successfully${NC}"
    else
      echo -e "${RED}Apply failed${NC}"
      exit 1
    fi
  else
    if terraform apply tfplan; then
      echo -e "${GREEN}Configuration applied successfully${NC}"
      rm -f tfplan
    else
      echo -e "${RED}Apply failed${NC}"
      exit 1
    fi
  fi
  echo ""
fi

echo -e "${YELLOW}Step 4: Retrieving resource outputs...${NC}"

if [[ "$STATE_IN_S3" == "true" ]]; then
  echo -e "${BLUE}Connected to existing remote state, extracting values from backend config...${NC}"

  S3_BUCKET=$(grep -E '^bucket\s*=' "environments/${ENV}/backend-config.hcl" | awk -F'"' '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || echo "")
  KMS_ALIAS=$(grep -E '^kms_key_id\s*=' "environments/${ENV}/backend-config.hcl" | awk -F'"' '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || echo "")
  REGION=$(grep -E '^region\s*=' "environments/${ENV}/backend-config.hcl" | awk -F'"' '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || echo "")

  KMS_ALIAS=$(echo "$KMS_ALIAS" | sed 's/^alias\///')

  echo -e "${GREEN}Values extracted from backend config:${NC}"
  echo -e "   S3 Bucket: ${S3_BUCKET}"
  echo -e "   KMS Alias: alias/${KMS_ALIAS}"
  echo -e "   Region: ${REGION}"
else
  S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null || echo "")
  KMS_ALIAS=$(terraform output -raw kms_key_alias 2>/dev/null || echo "")
  REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

  if [[ -z "$S3_BUCKET" ]] || [[ -z "$KMS_ALIAS" ]] || [[ -z "$REGION" ]]; then
    echo -e "${RED}Error: Failed to retrieve required outputs${NC}"
    echo -e "${RED}   S3 Bucket: ${S3_BUCKET:-NOT FOUND}${NC}"
    echo -e "${RED}   KMS Alias: ${KMS_ALIAS:-NOT FOUND}${NC}"
    echo -e "${RED}   Region: ${REGION:-NOT FOUND}${NC}"
    exit 1
  fi

  echo -e "${GREEN}Outputs retrieved:${NC}"
  echo -e "   S3 Bucket: ${S3_BUCKET}"
  echo -e "   KMS Alias: ${KMS_ALIAS}"
  echo -e "   Region: ${REGION}"
fi
echo ""


echo -e "${YELLOW}Step 5: Updating backend configuration...${NC}"

TEMPLATE_FILE="${TERRAFORM_DIR}/backend-config.hcl.template"
OUTPUT_FILE="${TERRAFORM_DIR}/environments/${ENV}/backend-config.hcl"

if generate_backend_config_from_template "$TEMPLATE_FILE" "$OUTPUT_FILE" "$S3_BUCKET" "bootstrap/terraform.tfstate" "$REGION" "$KMS_ALIAS" "$ENV"; then
  echo -e "${GREEN}Backend configuration updated: environments/${ENV}/backend-config.hcl${NC}"
else
  echo -e "${RED}Failed to generate backend configuration from template${NC}"
  exit 1
fi
echo ""

echo -e "${YELLOW}Step 5b: Updating backend configuration for all layers...${NC}"

get_layer_state_key() {
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

UPDATED_COUNT=0
SKIPPED_COUNT=0

for LAYER_DIR in "${PROJECT_ROOT}"/0*-*/terraform; do
  if [[ ! -d "$LAYER_DIR" ]]; then
    continue
  fi

  LAYER_NAME=$(basename "$(dirname "$LAYER_DIR")")
  TEMPLATE_FILE="${LAYER_DIR}/backend-config.hcl.template"
  BACKEND_CONFIG_FILE="${LAYER_DIR}/environments/${ENV}/backend-config.hcl"

  if [[ ! -f "$TEMPLATE_FILE" ]]; then
    echo -e "${YELLOW}   Skipping ${LAYER_NAME}: backend-config.hcl.template not found${NC}"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    continue
  fi

  STATE_KEY=$(get_layer_state_key "$LAYER_NAME")
  if [[ -z "$STATE_KEY" ]]; then
    if [[ -f "$BACKEND_CONFIG_FILE" ]] && grep -qE '^key\s*=' "$BACKEND_CONFIG_FILE"; then
      STATE_KEY=$(grep -E '^key\s*=' "$BACKEND_CONFIG_FILE" | awk -F'"' '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || echo "")
    fi
    if [[ -z "$STATE_KEY" ]]; then
      # Fallback: derive from layer name
      LAYER_SHORT="${LAYER_NAME#[0-9]*-}"
      STATE_KEY="${LAYER_SHORT}/terraform.tfstate"
    fi
  fi

  EXISTING_REGION="$REGION"
  if [[ -f "$BACKEND_CONFIG_FILE" ]] && grep -qE '^region\s*=' "$BACKEND_CONFIG_FILE"; then
    EXISTING_REGION=$(grep -E '^region\s*=' "$BACKEND_CONFIG_FILE" | awk -F'"' '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || echo "$REGION")
  fi

  LAYER_KMS_ALIAS="alias/kms-${org_moniker}-${product_moniker}-${ENV}-${aws_region_short}-tfstate"
  LAYER_KMS_ARN=$(aws kms describe-key --key-id "$LAYER_KMS_ALIAS" --region "$EXISTING_REGION" --query 'KeyMetadata.Arn' --output text 2>/dev/null || echo "$LAYER_KMS_ALIAS")
  LAYER_KMS_ARN_ESCAPED=$(echo "$LAYER_KMS_ARN" | sed 's/\//\\\//g')

  if generate_backend_config_from_template "$TEMPLATE_FILE" "$BACKEND_CONFIG_FILE" "$S3_BUCKET" "$STATE_KEY" "$EXISTING_REGION" "$LAYER_KMS_ARN_ESCAPED" "$ENV"; then
    echo -e "${GREEN}   Updated ${LAYER_NAME}/terraform/environments/${ENV}/backend-config.hcl${NC}"
    echo -e "${BLUE}      State key: ${STATE_KEY}${NC}"
    UPDATED_COUNT=$((UPDATED_COUNT + 1))
  else
    echo -e "${RED}   Failed to generate ${LAYER_NAME}/terraform/environments/${ENV}/backend-config.hcl${NC}"
  fi
done

echo ""
echo -e "${GREEN}Updated ${UPDATED_COUNT} backend configuration file(s)${NC}"
if [[ $SKIPPED_COUNT -gt 0 ]]; then
  echo -e "${YELLOW}   Skipped ${SKIPPED_COUNT} layer(s) (backend-config.hcl.template not found)${NC}"
fi
echo ""

if [[ "$STATE_IN_S3" == "false" ]]; then
  echo -e "${YELLOW}Step 6: Migrating state to S3 backend...${NC}"

  if [ -f "backend.tf.bak" ]; then
    mv backend.tf.bak backend.tf
    echo -e "${BLUE}   Restored S3 backend configuration${NC}"
  fi

  if [[ "$AUTO_APPROVE" == "false" ]]; then
    echo -e "${YELLOW}This will migrate your state from local to S3 backend.${NC}"
    echo -e "${YELLOW}   Press Enter to continue, or Ctrl+C to cancel...${NC}"
    read -r
  fi

  if terraform init -migrate-state -backend-config="environments/${ENV}/backend-config.hcl"; then
    echo -e "${GREEN}State migrated to S3 backend successfully${NC}"
  else
    echo -e "${RED}State migration failed${NC}"
    exit 1
  fi
  echo ""
else
  echo -e "${YELLOW}Step 6: Skipping state migration (state already in S3)${NC}"
  echo ""
fi

echo -e "${YELLOW}Step 7: Verifying deployment...${NC}"

if terraform state list > /dev/null 2>&1; then
  echo -e "${GREEN}State is accessible${NC}"
else
  echo -e "${RED}Warning: Could not verify state access${NC}"
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [[ "$STATE_IN_S3" == "true" ]]; then
  echo -e "${GREEN}Connected to Existing Remote State Successfully!${NC}"
else
  echo -e "${GREEN}Bootstrap Layer Deployed Successfully!${NC}"
fi
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
if [[ "$STATE_IN_S3" == "false" ]]; then
  echo -e "${BLUE}Resource Outputs:${NC}"
  terraform output
  echo ""
fi
echo -e "${BLUE}Next Steps:${NC}"
echo -e "   1. All backend-config.hcl files have been automatically updated"
echo -e "   2. You can now deploy other layers using:"
echo -e "      ./scripts/deploy.sh governance ${ENV}"
echo -e "      ./scripts/deploy.sh infrastructure ${ENV}"
echo -e "      ./scripts/deploy.sh data-and-ai ${ENV}"
echo -e "      ./scripts/deploy.sh compute ${ENV}"
echo ""
