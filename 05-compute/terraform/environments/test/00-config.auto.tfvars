# Environment-specific configuration
# Common values (aws_region, aws_account_id, org, org_moniker, client, client_name, semantic_version, deployed_at)
# are loaded from ../../common.auto.tfvars
#
# Default values (enable_* flags, etc.) are defined in variables.tf
# Only environment-specific overrides are defined here

environment = "test"

# Terraform State Configuration (from bootstrap layer)
# These are required for remote state access to infrastructure layer
# Also used for backend configuration during terraform init
terraform_state_bucket         = "" # Set from bootstrap layer output: s3_bucket_name
terraform_state_dynamodb_table = "" # Set from bootstrap layer output: dynamodb_table_name
terraform_state_kms_key_id     = "" # Set from bootstrap layer output: kms_key_alias or kms_key_arn

# EKS Cluster Configuration (test environment)
eks_cluster_version              = "1.28"
eks_endpoint_public_access       = true
eks_endpoint_private_access      = true
eks_endpoint_public_access_cidrs = ["0.0.0.0/0"] # Restrict in production
eks_cluster_log_retention_days   = 7

# EKS Node Group Configuration (test environment)
eks_node_group_instance_types = ["m6i.large"]
eks_node_group_desired_size   = 2
eks_node_group_min_size       = 1
eks_node_group_max_size       = 4
eks_node_group_disk_size      = 50

# ECR Repositories (test environment)
ecr_repositories = [
  {
    name                 = "app-backend"
    image_tag_mutability = "MUTABLE"
    scan_on_push         = true
  },
  {
    name                 = "app-frontend"
    image_tag_mutability = "MUTABLE"
    scan_on_push         = true
  }
]

# ECR Pull Through Cache (test environment)
ecr_pull_through_cache_upstream_registries = [
  "docker.io",
  "public.ecr.aws",
  "quay.io",
  "ghcr.io",
  "uniqueapp.azurecr.io" # Unique Azure Container Registry
]

# Azure Container Registry Configuration (test environment)
acr_registry_url = "uniqueapp.azurecr.io"
acr_username     = "" # Set ACR access key username
acr_password     = "" # Set ACR access key (sensitive - use environment variable or secret)

# Retention Configuration
cloudwatch_log_retention_days = 30

