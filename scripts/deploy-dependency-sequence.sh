#!/bin/bash
#######################################
# Deploy Layers in Dependency Sequence
#######################################
#
# Deploys Terraform layers in the correct dependency order:
# 1. Infrastructure Layer (provides VPC endpoints, KMS keys)
# 2. Data and AI Layer (uses infrastructure outputs)
#
# Usage:
#   ./scripts/deploy-dependency-sequence.sh <environment> [--auto-approve] [--skip-plan]
#
# Examples:
#   ./scripts/deploy-dependency-sequence.sh sbx
#   ./scripts/deploy-dependency-sequence.sh sbx --auto-approve
#   ./scripts/deploy-dependency-sequence.sh sbx --skip-plan --auto-approve
#######################################

set -euo pipefail

# Get the script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Parse arguments
ENV="${1:-sbx}"
AUTO_APPROVE=""
SKIP_PLAN=""

for arg in "$@"; do
  case $arg in
    --auto-approve)
      AUTO_APPROVE="--auto-approve"
      ;;
    --skip-plan)
      SKIP_PLAN="--skip-plan"
      ;;
  esac
done

# Validate environment
if [[ ! "$ENV" =~ ^(dev|test|prod|sbx)$ ]]; then
  echo -e "${RED}❌ Error: Environment must be one of: dev, test, prod, sbx${NC}"
  exit 1
fi

# Build deploy command arguments
DEPLOY_ARGS=("$ENV")
if [[ -n "$AUTO_APPROVE" ]]; then
  DEPLOY_ARGS+=("$AUTO_APPROVE")
fi
if [[ -n "$SKIP_PLAN" ]]; then
  DEPLOY_ARGS+=("$SKIP_PLAN")
fi

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Deploying Layers in Dependency Sequence${NC}"
echo -e "${CYAN}Environment: ${ENV}${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

#######################################
# Step 1: Infrastructure Layer
#######################################
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 1/2: Deploying Infrastructure Layer${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}This layer provides:${NC}"
echo -e "${YELLOW}  • S3 Gateway Endpoint (required for S3 VPC-only bucket policies)${NC}"
echo -e "${YELLOW}  • CloudWatch Logs KMS key (required for Bedrock logging)${NC}"
echo -e "${YELLOW}  • VPC, subnets, security groups${NC}"
echo ""

if ! "${SCRIPT_DIR}/deploy.sh" infrastructure "${DEPLOY_ARGS[@]}"; then
  echo -e "${RED}❌ Infrastructure layer deployment failed${NC}"
  exit 1
fi

echo ""
echo -e "${GREEN}✓ Infrastructure layer deployed successfully${NC}"
echo ""

#######################################
# Step 2: Data and AI Layer
#######################################
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Step 2/2: Deploying Data and AI Layer${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}This layer uses infrastructure outputs:${NC}"
echo -e "${YELLOW}  • S3 Gateway Endpoint ID (for VPC-only bucket policies)${NC}"
echo -e "${YELLOW}  • CloudWatch Logs KMS key (for Bedrock logging encryption)${NC}"
echo -e "${YELLOW}  • VPC ID, subnet IDs, KMS keys${NC}"
echo ""

if ! "${SCRIPT_DIR}/deploy.sh" data-and-ai "${DEPLOY_ARGS[@]}"; then
  echo -e "${RED}❌ Data and AI layer deployment failed${NC}"
  exit 1
fi

echo ""
echo -e "${GREEN}✓ Data and AI layer deployed successfully${NC}"
echo ""

#######################################
# Summary
#######################################
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Deployment Sequence Complete${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GREEN}Deployed layers:${NC}"
echo -e "${GREEN}  ✓ Infrastructure Layer${NC}"
echo -e "${GREEN}  ✓ Data and AI Layer${NC}"
echo ""
echo -e "${YELLOW}Changes deployed:${NC}"
echo -e "${YELLOW}  • S3 buckets configured for VPC-only access${NC}"
echo -e "${YELLOW}  • Bedrock logging configured for CloudWatch Logs${NC}"
echo ""

