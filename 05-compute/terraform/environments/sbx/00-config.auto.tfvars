# Environment-specific configuration
# Common values (aws_region, aws_account_id, org, org_moniker, client, client_name, semantic_version, deployed_at)
# are loaded from ../../common.auto.tfvars
#
# Default values (enable_* flags, etc.) are defined in variables.tf
# Only environment-specific overrides are defined here

environment = "sbx"

# Client Configuration (override default "acme" to match actual deployment)
client = "dogfood"

# Terraform State Configuration (from bootstrap layer)
# These are computed dynamically from naming module (same as bootstrap layer)
# Format: s3-{id_short}-tfstate (e.g., s3-uq-dogfood-x-euc2-tfstate)
# Format: alias/kms-{id}-tfstate (e.g., alias/kms-uq-dogfood-sbx-euc2-tfstate)
terraform_state_bucket     = "s3-uq-dogfood-x-euc2-tfstate"
terraform_state_kms_key_id = "alias/kms-uq-dogfood-sbx-euc2-tfstate"

# EKS Cluster Configuration (sandbox environment - internal only)
eks_cluster_version              = "1.34"
eks_endpoint_public_access       = false
eks_endpoint_private_access      = true
eks_endpoint_public_access_cidrs = []
eks_cluster_log_retention_days   = 7

# EKS Node Group Configuration (sandbox environment - scaled up for Kong)
eks_node_group_instance_types = ["m6i.2xlarge"]
eks_node_group_desired_size   = 1
eks_node_group_min_size       = 1
eks_node_group_max_size       = 2
eks_node_group_disk_size      = 50

# ECR Repositories (sandbox environment)
ecr_repositories = []

# ECR Pull Through Cache (sandbox environment)
ecr_pull_through_cache_upstream_registries = [
  "public.ecr.aws",
  "uniquecr.azurecr.io", # Full ACR URL (matches acr_registry_url)
  "uniquecr"             # Short alias for uniquecr.azurecr.io (mapped in locals.tf)
]

# Azure Container Registry Configuration (sandbox environment)
# Set credentials via environment variables: TF_VAR_acr_username and TF_VAR_acr_password
# Note: uniquecr alias maps to uniquecr.azurecr.io (configured in locals.tf)
acr_registry_url = "uniquecr.azurecr.io"
acr_username     = ""
acr_password     = ""

# Retention Configuration (overridden for fast teardown in sandbox)
cloudwatch_log_retention_days = 7

# Transit Gateway Configuration
# Transit Gateway ID from connectivity layer (landing zone account)
# The Transit Gateway must be shared via AWS RAM from the connectivity account.
# Once shared, this attachment will be automatically accepted.
transit_gateway_id = "tgw-0d30c988e22108053"

# VPC Endpoints Configuration
# Required for EKS API access from private subnets (internal-only deployment)
enable_eks_endpoint = true # Required for kubectl and EKS API calls without internet access

# Route 53 DNS Configuration
# Route 53 Private Hosted Zone is managed in infrastructure layer

# CloudFront VPC Origin Configuration
# ALB will be created automatically to forward to Kong NLB
# These values should be provided via environment variables or other secure means
# kong_nlb_dns_name         = ""  # Set via TF_VAR_kong_nlb_dns_name
# kong_nlb_security_group_id = ""  # Set via TF_VAR_kong_nlb_security_group_id

# Legacy: Keep for backward compatibility (will be overridden by CloudFront ALB)
# internal_alb_arn_override = null

