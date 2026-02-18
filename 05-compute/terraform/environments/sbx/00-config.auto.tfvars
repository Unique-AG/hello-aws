# Environment-specific configuration
# Common values (aws_region, aws_account_id, org, org_moniker, product, product_moniker, semantic_version)
# are loaded from ../../common.auto.tfvars
#
# Default values (enable_* flags, etc.) are defined in variables.tf
# Only environment-specific overrides are defined here

environment = "sbx"

# EKS Cluster Configuration (sandbox — public access for development)
eks_cluster_version              = "1.34"
eks_endpoint_public_access       = true
eks_endpoint_private_access      = true
eks_endpoint_public_access_cidrs = ["0.0.0.0/0"]
eks_cluster_log_retention_days   = 7

# EKS Node Group Configuration
eks_node_groups = {
  steady = {
    instance_types  = ["m6i.2xlarge"]
    desired_size    = 2
    min_size        = 0
    max_size        = 4
    max_unavailable = 2
    labels = {
      lifecycle   = "persistent"
      scalability = "steady"
    }
    taints = []
  }
  rapid = {
    instance_types = ["m6i.2xlarge"]
    desired_size   = 0
    min_size       = 0
    max_size       = 3
    labels = {
      lifecycle   = "ephemeral"
      scalability = "rapid"
    }
  }
}

# ECR Pull-Through Cache
ecr_pull_through_cache_upstream_registries = [
  "public.ecr.aws",
  "example.azurecr.io",  # Your Azure Container Registry URL
  "example",             # ACR short alias (extracted from URL)
  "quay.io",
]

# VPC Endpoints
enable_eks_endpoint = true
