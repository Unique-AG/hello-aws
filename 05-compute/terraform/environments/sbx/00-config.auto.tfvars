# Environment-specific configuration
# Common values (aws_region, aws_account_id, org, org_moniker, client, client_name, semantic_version, deployed_at)
# are loaded from ../../common.auto.tfvars
#
# Default values (enable_* flags, etc.) are defined in variables.tf
# Only environment-specific overrides are defined here

environment = "sbx"

# Terraform State Configuration (from bootstrap layer)
# These are computed dynamically from naming module (same as bootstrap layer)
# Format: s3-{id_short}-tfstate (e.g., s3-uq-dogfood-x-euc2-tfstate)
# Format: alias/kms-{id}-tfstate (e.g., alias/kms-uq-dogfood-sbx-euc2-tfstate)
# Uncomment and set manually if you need to override the computed values:
# terraform_state_bucket     = ""
# terraform_state_kms_key_id = ""

# EKS Cluster Configuration (sandbox environment)
eks_cluster_version              = "1.34"
eks_endpoint_public_access       = true
eks_endpoint_private_access      = true
eks_endpoint_public_access_cidrs = ["0.0.0.0/0"]
eks_cluster_log_retention_days   = 7

# EKS Node Group Configuration (sandbox environment - minimal for cost)
eks_node_group_instance_types = ["m6i.large"]
eks_node_group_desired_size   = 1
eks_node_group_min_size       = 1
eks_node_group_max_size       = 2
eks_node_group_disk_size      = 50

# ECR Repositories (sandbox environment)
ecr_repositories = []

# ECR Pull Through Cache (sandbox environment)
ecr_pull_through_cache_upstream_registries = [
  "public.ecr.aws",
  "uniquecr.azurecr.io",  # Full ACR URL (matches acr_registry_url)
  "uniquecr"  # Short alias for uniquecr.azurecr.io (mapped in locals.tf)
]

# Azure Container Registry Configuration (sandbox environment)
# Set credentials via environment variables: TF_VAR_acr_username and TF_VAR_acr_password
# Note: uniquecr alias maps to uniquecr.azurecr.io (configured in locals.tf)
acr_registry_url = "uniquecr.azurecr.io"
acr_username     = ""
acr_password     = ""

# Retention Configuration (overridden for fast teardown in sandbox)
cloudwatch_log_retention_days = 7

