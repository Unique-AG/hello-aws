#!/usr/bin/env bash
# configure-instance.sh — Apply instance-specific values from instance-config.yaml
#
# Usage:
#   cd 06-applications
#   ./scripts/configure-instance.sh <env>
#   ./scripts/configure-instance.sh sbx
#
# Requires: yq (https://github.com/mikefarah/yq)
#
# This script is idempotent — safe to re-run. It tracks what values are
# currently applied (in <env>/.instance-applied.yaml) and replaces them with
# the values from <env>/instance-config.yaml.
#
# On first run against a fresh clone, the YAML files contain <PLACEHOLDER>
# tokens which are replaced with the real values from instance-config.yaml.
#
# Only files under the specified environment directory are modified — other
# environments on the same branch are not affected.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ------------------------------------------------------------------
# Environment argument
# ------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <env>"
  echo "  e.g. $0 sbx"
  exit 1
fi

ENV="$1"
ENV_DIR="$BASE_DIR/$ENV"
CONFIG="$ENV_DIR/instance-config.yaml"
STATE="$ENV_DIR/.instance-applied.yaml"

if [[ ! -d "$ENV_DIR" ]]; then
  echo "ERROR: Environment directory $ENV_DIR not found."
  exit 1
fi

# ------------------------------------------------------------------
# Preflight
# ------------------------------------------------------------------
if ! command -v yq &>/dev/null; then
  echo "ERROR: yq is required but not installed."
  echo "  brew install yq   OR   https://github.com/mikefarah/yq#install"
  exit 1
fi

if [[ ! -f "$CONFIG" ]]; then
  echo "ERROR: $CONFIG not found."
  echo "  cp instance-config.yaml.template $ENV/instance-config.yaml"
  echo "  # Edit $ENV/instance-config.yaml with your values"
  exit 1
fi

# ------------------------------------------------------------------
# Origin values (placeholder tokens for a fresh upstream clone)
# ------------------------------------------------------------------
origin_config() {
  cat <<'ORIGIN_EOF'
github:
  repoURL: "<GITHUB_REPO_URL>"
  targetRevision: "<GIT_TARGET_REVISION>"
domain:
  base: "<DOMAIN_BASE>"
  api: "<DOMAIN_API>"
  identity: "<DOMAIN_IDENTITY>"
  argocd: "<DOMAIN_ARGOCD>"
  dnsZone: "<DNS_ZONE>"
aws:
  region: "<AWS_REGION>"
  accountId: "<AWS_ACCOUNT_ID>"
  hostedZoneID: "<AWS_HOSTED_ZONE_ID>"
  kms:
    keyArn: "<KMS_KEY_ARN>"
  eks:
    clusterName: "<EKS_CLUSTER_NAME>"
  vpc:
    id: "<VPC_ID>"
  route53:
    privateZoneId: "<ROUTE53_PRIVATE_ZONE_ID>"
  connectivity:
    accountId: "<CONNECTIVITY_ACCOUNT_ID>"
  nlb:
    targetGroupHttpArn: "<TARGET_GROUP_HTTP_ARN>"
    targetGroupHttpsArn: "<TARGET_GROUP_HTTPS_ARN>"
  redis:
    url: "<REDIS_URL>"
  bedrock:
    cohereEmbedV4ProfileId: "<BEDROCK_COHERE_EMBED_V4_PROFILE_ID>"
    minimaxRegion: "<BEDROCK_MINIMAX_REGION>"
  prometheus:
    workspaceId: "<AMP_WORKSPACE_ID>"
    remoteWriteUrl: "<AMP_REMOTE_WRITE_URL>"
  observability:
    s3BucketName: "<OBSERVABILITY_S3_BUCKET_NAME>"
  ecr:
    primary:
      accountId: "000000000000"
      prefix: uniquecr
    thirdParty:
      accountId: "000000000000"
      prefix: uniquecr
zitadel:
  projectId: "<ZITADEL_PROJECT_ID>"
  clientId: "<ZITADEL_CLIENT_ID>"
  orgId: "<ZITADEL_ORG_ID>"
ORIGIN_EOF
}

# ------------------------------------------------------------------
# Determine "from" values (state file if exists, else origin defaults)
# ------------------------------------------------------------------
if [[ -f "$STATE" ]]; then
  FROM="$STATE"
  echo "Using previously applied state from $ENV/.instance-applied.yaml"
else
  FROM_TMP=$(mktemp)
  origin_config > "$FROM_TMP"
  FROM="$FROM_TMP"
  echo "No state file found — using placeholder tokens"
fi

# ------------------------------------------------------------------
# Helper: check if a value is a placeholder token
# ------------------------------------------------------------------
is_placeholder() { [[ "$1" == "<"*">" ]]; }

# ------------------------------------------------------------------
# Read "from" (current) values
# ------------------------------------------------------------------
FROM_REPO_URL=$(yq '.github.repoURL' "$FROM")
FROM_TARGET_REV=$(yq '.github.targetRevision' "$FROM")
FROM_DOMAIN_BASE=$(yq '.domain.base' "$FROM")
FROM_DOMAIN_API=$(yq '.domain.api' "$FROM")
FROM_DOMAIN_IDENTITY=$(yq '.domain.identity' "$FROM")
FROM_DOMAIN_ARGOCD=$(yq '.domain.argocd' "$FROM")
FROM_DNS_ZONE=$(yq '.domain.dnsZone' "$FROM")
FROM_AWS_REGION=$(yq '.aws.region' "$FROM")
FROM_AWS_ACCOUNT_ID=$(yq '.aws.accountId' "$FROM")
FROM_HOSTED_ZONE_ID=$(yq '.aws.hostedZoneID' "$FROM")
FROM_ECR_PRIMARY_ACCOUNT=$(yq '.aws.ecr.primary.accountId' "$FROM")
FROM_ECR_PRIMARY_PREFIX=$(yq '.aws.ecr.primary.prefix' "$FROM")
FROM_ECR_THIRDPARTY_ACCOUNT=$(yq '.aws.ecr.thirdParty.accountId' "$FROM")
FROM_ECR_THIRDPARTY_PREFIX=$(yq '.aws.ecr.thirdParty.prefix' "$FROM")
FROM_KMS_KEY_ARN=$(yq '.aws.kms.keyArn' "$FROM")
FROM_EKS_CLUSTER_NAME=$(yq '.aws.eks.clusterName' "$FROM")
FROM_VPC_ID=$(yq '.aws.vpc.id' "$FROM")
FROM_ROUTE53_PRIVATE_ZONE_ID=$(yq '.aws.route53.privateZoneId' "$FROM")
FROM_CONNECTIVITY_ACCOUNT_ID=$(yq '.aws.connectivity.accountId' "$FROM")
FROM_TG_HTTP_ARN=$(yq '.aws.nlb.targetGroupHttpArn' "$FROM")
FROM_TG_HTTPS_ARN=$(yq '.aws.nlb.targetGroupHttpsArn' "$FROM")
FROM_REDIS_URL=$(yq '.aws.redis.url' "$FROM")
FROM_BEDROCK_COHERE_PROFILE_ID=$(yq '.aws.bedrock.cohereEmbedV4ProfileId' "$FROM")
FROM_BEDROCK_MINIMAX_REGION=$(yq '.aws.bedrock.minimaxRegion // "<BEDROCK_MINIMAX_REGION>"' "$FROM")
FROM_AMP_WORKSPACE_ID=$(yq '.aws.prometheus.workspaceId // "<AMP_WORKSPACE_ID>"' "$FROM")
FROM_AMP_REMOTE_WRITE_URL=$(yq '.aws.prometheus.remoteWriteUrl // "<AMP_REMOTE_WRITE_URL>"' "$FROM")
FROM_OBSERVABILITY_S3_BUCKET=$(yq '.aws.observability.s3BucketName // "<OBSERVABILITY_S3_BUCKET_NAME>"' "$FROM")
FROM_ZITADEL_PROJECT_ID=$(yq '.zitadel.projectId' "$FROM")
FROM_ZITADEL_CLIENT_ID=$(yq '.zitadel.clientId' "$FROM")
FROM_ZITADEL_ORG_ID=$(yq '.zitadel.orgId' "$FROM")

# Clean up temp file if used
[[ -v FROM_TMP ]] && rm -f "$FROM_TMP"

# Derived "from" values — handle placeholders vs real values
if is_placeholder "$FROM_AWS_REGION"; then
  # Placeholder mode: YAML files contain full placeholder tokens
  FROM_ECR_PRIMARY_FULL="<ECR_REGISTRY_PRIMARY>"
  FROM_ECR_THIRDPARTY_FULL="<ECR_REGISTRY_THIRDPARTY>"
  FROM_ECR_THIRDPARTY_BARE="<ECR_REGISTRY_THIRDPARTY_BARE>"
else
  # Real values: construct ECR URLs from components
  FROM_ECR_PRIMARY="${FROM_ECR_PRIMARY_ACCOUNT}.dkr.ecr.${FROM_AWS_REGION}.amazonaws.com"
  FROM_ECR_THIRDPARTY="${FROM_ECR_THIRDPARTY_ACCOUNT}.dkr.ecr.${FROM_AWS_REGION}.amazonaws.com"
  FROM_ECR_PRIMARY_FULL="${FROM_ECR_PRIMARY}/${FROM_ECR_PRIMARY_PREFIX}"
  FROM_ECR_THIRDPARTY_FULL="${FROM_ECR_THIRDPARTY}/${FROM_ECR_THIRDPARTY_PREFIX}"
  FROM_ECR_THIRDPARTY_BARE="${FROM_ECR_THIRDPARTY}"
fi

# ------------------------------------------------------------------
# Read "to" (desired) values from instance-config.yaml
# ------------------------------------------------------------------
TO_REPO_URL=$(yq '.github.repoURL' "$CONFIG")
TO_TARGET_REV=$(yq '.github.targetRevision' "$CONFIG")
TO_DOMAIN_BASE=$(yq '.domain.base' "$CONFIG")
TO_DOMAIN_API=$(yq '.domain.api' "$CONFIG")
TO_DOMAIN_IDENTITY=$(yq '.domain.identity' "$CONFIG")
TO_DOMAIN_ARGOCD=$(yq '.domain.argocd' "$CONFIG")
TO_DNS_ZONE=$(yq '.domain.dnsZone' "$CONFIG")
TO_AWS_REGION=$(yq '.aws.region' "$CONFIG")
TO_AWS_ACCOUNT_ID=$(yq '.aws.accountId' "$CONFIG")
TO_HOSTED_ZONE_ID=$(yq '.aws.hostedZoneID' "$CONFIG")
TO_ECR_PRIMARY_ACCOUNT=$(yq '.aws.ecr.primary.accountId' "$CONFIG")
TO_ECR_PRIMARY_PREFIX=$(yq '.aws.ecr.primary.prefix' "$CONFIG")
TO_ECR_THIRDPARTY_ACCOUNT=$(yq '.aws.ecr.thirdParty.accountId' "$CONFIG")
TO_ECR_THIRDPARTY_PREFIX=$(yq '.aws.ecr.thirdParty.prefix' "$CONFIG")
TO_KMS_KEY_ARN=$(yq '.aws.kms.keyArn' "$CONFIG")
TO_EKS_CLUSTER_NAME=$(yq '.aws.eks.clusterName' "$CONFIG")
TO_VPC_ID=$(yq '.aws.vpc.id' "$CONFIG")
TO_ROUTE53_PRIVATE_ZONE_ID=$(yq '.aws.route53.privateZoneId' "$CONFIG")
TO_CONNECTIVITY_ACCOUNT_ID=$(yq '.aws.connectivity.accountId' "$CONFIG")
TO_TG_HTTP_ARN=$(yq '.aws.nlb.targetGroupHttpArn' "$CONFIG")
TO_TG_HTTPS_ARN=$(yq '.aws.nlb.targetGroupHttpsArn' "$CONFIG")
TO_REDIS_URL=$(yq '.aws.redis.url' "$CONFIG")
TO_BEDROCK_COHERE_PROFILE_ID=$(yq '.aws.bedrock.cohereEmbedV4ProfileId' "$CONFIG")
TO_BEDROCK_MINIMAX_REGION=$(yq '.aws.bedrock.minimaxRegion' "$CONFIG")
TO_AMP_WORKSPACE_ID=$(yq '.aws.prometheus.workspaceId' "$CONFIG")
TO_AMP_REMOTE_WRITE_URL=$(yq '.aws.prometheus.remoteWriteUrl' "$CONFIG")
TO_OBSERVABILITY_S3_BUCKET=$(yq '.aws.observability.s3BucketName' "$CONFIG")
TO_ZITADEL_PROJECT_ID=$(yq '.zitadel.projectId' "$CONFIG")
TO_ZITADEL_CLIENT_ID=$(yq '.zitadel.clientId' "$CONFIG")
TO_ZITADEL_ORG_ID=$(yq '.zitadel.orgId' "$CONFIG")

# Derived "to" values (always real — instance-config has actual values)
TO_ECR_PRIMARY="${TO_ECR_PRIMARY_ACCOUNT}.dkr.ecr.${TO_AWS_REGION}.amazonaws.com"
TO_ECR_THIRDPARTY="${TO_ECR_THIRDPARTY_ACCOUNT}.dkr.ecr.${TO_AWS_REGION}.amazonaws.com"
TO_ECR_PRIMARY_FULL="${TO_ECR_PRIMARY}/${TO_ECR_PRIMARY_PREFIX}"
TO_ECR_THIRDPARTY_FULL="${TO_ECR_THIRDPARTY}/${TO_ECR_THIRDPARTY_PREFIX}"

# ACR (Azure Container Registry) derived values — for tfvars ECR pull-through cache entries
TO_ACR_URL="${TO_ECR_PRIMARY_PREFIX}.azurecr.io"
TO_ACR_ALIAS="$TO_ECR_PRIMARY_PREFIX"

# ------------------------------------------------------------------
# Helper: sed replacement (portable macOS + Linux)
# ------------------------------------------------------------------
do_sed() {
  local pattern="$1"
  shift
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' "$pattern" "$@"
  else
    sed -i "$pattern" "$@"
  fi
}

# Replace a string in all YAML files under the environment directory
# (excluding instance-config.yaml and .instance-applied.yaml)
replace_all() {
  local old="$1"
  local new="$2"

  if [[ "$old" == "$new" ]]; then
    return 0
  fi

  # Escape special characters for sed
  local old_escaped new_escaped
  old_escaped=$(printf '%s\n' "$old" | sed 's/[&/\]/\\&/g')
  new_escaped=$(printf '%s\n' "$new" | sed 's/[&/\]/\\&/g')

  while IFS= read -r -d '' file; do
    if grep -qF "$old" "$file"; then
      do_sed "s|${old_escaped}|${new_escaped}|g" "$file"
    fi
  done < <(find "$ENV_DIR" -name '*.yaml' \
    -not -name 'instance-config.yaml' \
    -not -name '.instance-applied.yaml' \
    -print0)
}

# Replace a string in all tfvars files under the project's terraform layer
# environment directories (e.g., 03-infrastructure/terraform/environments/sbx/)
PROJECT_ROOT="$(cd "$BASE_DIR/.." && pwd)"
replace_all_tfvars() {
  local old="$1"
  local new="$2"

  if [[ "$old" == "$new" ]]; then
    return 0
  fi

  local old_escaped new_escaped
  old_escaped=$(printf '%s\n' "$old" | sed 's/[&/\]/\\&/g')
  new_escaped=$(printf '%s\n' "$new" | sed 's/[&/\]/\\&/g')

  while IFS= read -r -d '' file; do
    if grep -qF "$old" "$file"; then
      do_sed "s|${old_escaped}|${new_escaped}|g" "$file"
    fi
  done < <(find "$PROJECT_ROOT" -path "*/terraform/environments/$ENV/*.auto.tfvars" -print0)
}

# ------------------------------------------------------------------
# Apply replacements (order matters — longest/most-specific first)
# ------------------------------------------------------------------
echo "Configuring $ENV from $CONFIG ..."

# 1. ECR registries (full registry URL including prefix — must be before region replacement)
echo "  ECR primary registry ..."
replace_all "$FROM_ECR_PRIMARY_FULL" "$TO_ECR_PRIMARY_FULL"

echo "  ECR third-party registry ..."
replace_all "$FROM_ECR_THIRDPARTY_FULL" "$TO_ECR_THIRDPARTY_FULL"

# Also handle bare registry references (without prefix, e.g. in _common.yaml)
echo "  ECR third-party bare registry ..."
replace_all "$FROM_ECR_THIRDPARTY_BARE" "$TO_ECR_THIRDPARTY"

# 2. Redis URL (before region, since URL contains region)
echo "  Redis URL ..."
replace_all "$FROM_REDIS_URL" "$TO_REDIS_URL"

# 3. Target group ARNs (before region, since ARNs contain region)
echo "  NLB target group HTTP ARN ..."
replace_all "$FROM_TG_HTTP_ARN" "$TO_TG_HTTP_ARN"

echo "  NLB target group HTTPS ARN ..."
replace_all "$FROM_TG_HTTPS_ARN" "$TO_TG_HTTPS_ARN"

# 3. KMS key ARN (before region, since ARN contains region)
echo "  KMS key ARN ..."
replace_all "$FROM_KMS_KEY_ARN" "$TO_KMS_KEY_ARN"

# 3b. Bedrock inference profile ID (before account ID and region, since ARN contains both)
echo "  Bedrock Cohere Embed v4 profile ID ..."
replace_all "$FROM_BEDROCK_COHERE_PROFILE_ID" "$TO_BEDROCK_COHERE_PROFILE_ID"

# 3b-2. Bedrock MiniMax region (must run before the generic AWS region replacement
# at step 6; placeholder is region-shaped but distinct from <AWS_REGION>).
echo "  Bedrock MiniMax region ..."
replace_all "$FROM_BEDROCK_MINIMAX_REGION" "$TO_BEDROCK_MINIMAX_REGION"

# 3c. Prometheus / Observability (before region and account, since URLs contain both)
echo "  AMP remote write URL ..."
replace_all "$FROM_AMP_REMOTE_WRITE_URL" "$TO_AMP_REMOTE_WRITE_URL"

echo "  AMP workspace ID ..."
replace_all "$FROM_AMP_WORKSPACE_ID" "$TO_AMP_WORKSPACE_ID"

echo "  Observability S3 bucket ..."
replace_all "$FROM_OBSERVABILITY_S3_BUCKET" "$TO_OBSERVABILITY_S3_BUCKET"

# 3d. AWS account ID (before region, since ARNs contain both)
echo "  AWS account ID ..."
replace_all "$FROM_AWS_ACCOUNT_ID" "$TO_AWS_ACCOUNT_ID"

# 3. Repository URL (before domain, since URL contains github.com not our domain)
echo "  Repository URL ..."
replace_all "$FROM_REPO_URL" "$TO_REPO_URL"

# 4. Target revision in app specs
if [[ "$FROM_TARGET_REV" != "$TO_TARGET_REV" ]]; then
  echo "  Target revision ..."
  while IFS= read -r -d '' file; do
    if grep -qF "$TO_REPO_URL" "$file" || grep -qF "targetRevision:" "$file" || grep -qF "revision:" "$file"; then
      do_sed "s|revision: ${FROM_TARGET_REV}|revision: ${TO_TARGET_REV}|g" "$file"
      do_sed "s|targetRevision: ${FROM_TARGET_REV}|targetRevision: ${TO_TARGET_REV}|g" "$file"
    fi
  done < <(find "$ENV_DIR" -name '*.yaml' \
    -not -name 'instance-config.yaml' \
    -not -name '.instance-applied.yaml' \
    -print0)
fi

# 5. Domains (longest/most-specific first to avoid partial matches)
echo "  ArgoCD domain ..."
replace_all "$FROM_DOMAIN_ARGOCD" "$TO_DOMAIN_ARGOCD"

echo "  API domain ..."
replace_all "$FROM_DOMAIN_API" "$TO_DOMAIN_API"

echo "  Identity domain ..."
replace_all "$FROM_DOMAIN_IDENTITY" "$TO_DOMAIN_IDENTITY"

echo "  Base domain ..."
replace_all "$FROM_DOMAIN_BASE" "$TO_DOMAIN_BASE"

echo "  DNS zone ..."
replace_all "$FROM_DNS_ZONE" "$TO_DNS_ZONE"

# 6. AWS region (standalone references not already handled by ECR/KMS replacement)
echo "  AWS region ..."
replace_all "$FROM_AWS_REGION" "$TO_AWS_REGION"

# 7. Hosted zone ID
echo "  Hosted zone ID ..."
replace_all "$FROM_HOSTED_ZONE_ID" "$TO_HOSTED_ZONE_ID"

# 8. EKS cluster name
echo "  EKS cluster name ..."
replace_all "$FROM_EKS_CLUSTER_NAME" "$TO_EKS_CLUSTER_NAME"

# 9. VPC ID
echo "  VPC ID ..."
replace_all "$FROM_VPC_ID" "$TO_VPC_ID"

# 10. Zitadel IDs
echo "  Zitadel project ID ..."
replace_all "$FROM_ZITADEL_PROJECT_ID" "$TO_ZITADEL_PROJECT_ID"

echo "  Zitadel client ID ..."
replace_all "$FROM_ZITADEL_CLIENT_ID" "$TO_ZITADEL_CLIENT_ID"

echo "  Zitadel org ID ..."
replace_all "$FROM_ZITADEL_ORG_ID" "$TO_ZITADEL_ORG_ID"

# ------------------------------------------------------------------
# Terraform layer config replacements (00-config.auto.tfvars)
# ------------------------------------------------------------------
echo ""
echo "Configuring Terraform layer configs ..."

# Tfvars files use concrete dummy values on main (not angle-bracket tokens).
# Determine the correct "from" values based on whether state exists.
if [[ -f "$STATE" ]]; then
  # State exists: tfvars were previously configured with real values
  TFVARS_FROM_DOMAIN_BASE="$FROM_DOMAIN_BASE"
  TFVARS_FROM_ROUTE53_ZONE_ID="$FROM_ROUTE53_PRIVATE_ZONE_ID"
  TFVARS_FROM_CONNECTIVITY_ACCOUNT_ID="$FROM_CONNECTIVITY_ACCOUNT_ID"
  TFVARS_FROM_ACR_URL="${FROM_ECR_PRIMARY_PREFIX}.azurecr.io"
  TFVARS_FROM_ACR_ALIAS="$FROM_ECR_PRIMARY_PREFIX"
else
  # Fresh clone: tfvars contain these example/dummy values
  TFVARS_FROM_DOMAIN_BASE="sbx.example.com"
  TFVARS_FROM_ROUTE53_ZONE_ID="Z0000000000000000000"
  TFVARS_FROM_CONNECTIVITY_ACCOUNT_ID="000000000000"
  TFVARS_FROM_ACR_URL="example.azurecr.io"
  TFVARS_FROM_ACR_ALIAS="example"
fi

# Order matters: replace domain first (sbx.example.com contains "example"),
# then ACR URL (example.azurecr.io contains "example"), then ACR alias last.
echo "  Base domain (tfvars) ..."
replace_all_tfvars "$TFVARS_FROM_DOMAIN_BASE" "$TO_DOMAIN_BASE"

echo "  Route 53 private zone ID ..."
replace_all_tfvars "$TFVARS_FROM_ROUTE53_ZONE_ID" "$TO_ROUTE53_PRIVATE_ZONE_ID"

echo "  Connectivity account ID ..."
replace_all_tfvars "$TFVARS_FROM_CONNECTIVITY_ACCOUNT_ID" "$TO_CONNECTIVITY_ACCOUNT_ID"

echo "  ACR registry URL ..."
replace_all_tfvars "$TFVARS_FROM_ACR_URL" "$TO_ACR_URL"

echo "  ACR alias ..."
replace_all_tfvars "$TFVARS_FROM_ACR_ALIAS" "$TO_ACR_ALIAS"

# ------------------------------------------------------------------
# Enable Bedrock marketplace model agreements
# ------------------------------------------------------------------
# Third-party models (e.g., Cohere) require a marketplace agreement before use.
# This is idempotent — already-accepted agreements are silently skipped.
echo ""
echo "Enabling Bedrock marketplace model agreements ..."
BEDROCK_MODELS_REQUIRING_AGREEMENT=(
  "anthropic.claude-3-5-sonnet-20240620-v1:0"
  "anthropic.claude-3-haiku-20240307-v1:0"
  "anthropic.claude-sonnet-4-5-20250929-v1:0"
  "anthropic.claude-opus-4-5-20251101-v1:0"
  "anthropic.claude-haiku-4-5-20251001-v1:0"
  "cohere.embed-v4:0"
)
for model_id in "${BEDROCK_MODELS_REQUIRING_AGREEMENT[@]}"; do
  # Check if agreement exists
  AVAILABILITY=$(aws bedrock get-foundation-model-availability --model-id "$model_id" --region "$TO_AWS_REGION" \
    --query "agreementAvailability.status" --output text 2>/dev/null || echo "UNKNOWN")
  if [ "$AVAILABILITY" = "AVAILABLE" ]; then
    echo "  $model_id: already enabled"
  elif [ "$AVAILABILITY" = "NOT_AVAILABLE" ]; then
    echo "  $model_id: accepting marketplace agreement ..."
    OFFER_TOKEN=$(aws bedrock list-foundation-model-agreement-offers --model-id "$model_id" --region "$TO_AWS_REGION" \
      --query "offers[0].offerToken" --output text 2>/dev/null)
    if [ -n "$OFFER_TOKEN" ] && [ "$OFFER_TOKEN" != "None" ]; then
      aws bedrock create-foundation-model-agreement --model-id "$model_id" --offer-token "$OFFER_TOKEN" \
        --region "$TO_AWS_REGION" >/dev/null 2>&1 && echo "  $model_id: ✓ agreement accepted" || echo "  $model_id: ✗ failed to accept"
    else
      echo "  $model_id: ✗ no offer token available"
    fi
  else
    echo "  $model_id: status=$AVAILABILITY (skipping)"
  fi
done

# ------------------------------------------------------------------
# Save applied state
# ------------------------------------------------------------------
cp "$CONFIG" "$STATE"
echo ""
echo "Done. State saved to $ENV/.instance-applied.yaml"
echo "Run ./scripts/validate-instance.sh $ENV to verify."
