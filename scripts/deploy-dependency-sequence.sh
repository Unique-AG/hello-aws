#!/bin/bash
#######################################
# Deploy All Layers in Dependency Sequence
#######################################
#
# Deploys all Terraform layers in the correct dependency order:
# 1. Bootstrap (state management, CI/CD auth)
# 2. Governance (budgets, Config rules, IAM policies)
# 3. Infrastructure (VPC, subnets, endpoints, KMS)
# 4. Data and AI (Aurora, ElastiCache, S3, Bedrock)
# 5. Compute (EKS, ECR)
# 6. Applications (ArgoCD, Helmfile)
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

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Parse arguments
ENV="${1:-}"
EXTRA_ARGS=()

if [[ -z "$ENV" ]]; then
  echo -e "${RED}Error: Environment is required${NC}"
  echo -e "${YELLOW}   Usage: ./scripts/deploy-dependency-sequence.sh <environment> [--auto-approve] [--skip-plan]${NC}"
  exit 1
fi

for arg in "${@:2}"; do
  case $arg in
    --auto-approve|--skip-plan)
      EXTRA_ARGS+=("$arg")
      ;;
  esac
done

# Validate environment
if [[ ! "$ENV" =~ ^(dev|test|prod|sbx)$ ]]; then
  echo -e "${RED}Error: Environment must be one of: dev, test, prod, sbx${NC}"
  exit 1
fi

# Layer deployment order
LAYERS=(
  "bootstrap"
  "governance"
  "infrastructure"
  "data-and-ai"
  "compute"
  "applications"
)

TOTAL=${#LAYERS[@]}

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Deploying All Layers in Dependency Sequence${NC}"
echo -e "${CYAN}Environment: ${ENV}${NC}"
echo -e "${CYAN}Layers: ${TOTAL}${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

DEPLOYED=()
STEP=0

for layer in "${LAYERS[@]}"; do
  STEP=$((STEP + 1))

  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}Step ${STEP}/${TOTAL}: Deploying ${layer} layer${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  if ! "${SCRIPT_DIR}/deploy.sh" "$layer" "$ENV" "${EXTRA_ARGS[@]}"; then
    echo -e "${RED}${layer} layer deployment failed${NC}"
    echo ""
    echo -e "${GREEN}Successfully deployed before failure:${NC}"
    for d in "${DEPLOYED[@]}"; do
      echo -e "${GREEN}  ${d}${NC}"
    done
    exit 1
  fi

  DEPLOYED+=("$layer")
  echo ""
  echo -e "${GREEN}${layer} layer deployed successfully${NC}"
  echo ""
done

#######################################
# Summary
#######################################
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Deployment Sequence Complete${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${GREEN}Deployed layers:${NC}"
for d in "${DEPLOYED[@]}"; do
  echo -e "${GREEN}  ${d}${NC}"
done
echo ""
