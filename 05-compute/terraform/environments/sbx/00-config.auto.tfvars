# Environment-specific configuration
# Common values (aws_region, aws_account_id, org, org_moniker, product, product_moniker, semantic_version)
# are loaded from ../../common.auto.tfvars
#
# Default values (enable_* flags, etc.) are defined in variables.tf
# Only environment-specific overrides are defined here

environment = "sbx"

# EKS Cluster Configuration
# Private endpoint only — k8s API not internet-reachable. Developers reach the
# cluster via SSM session → bastion (management_server) → kubectl. Variable
# defaults (public=false, cidrs=[]) already enforce this; the previous
# permissive overrides have been removed.
eks_cluster_version              = "1.35"
eks_endpoint_private_access      = true
eks_cluster_log_retention_days   = 7

# EKS Node Group Configuration
eks_node_groups = {
  steady = {
    instance_types  = ["m6i.2xlarge"]
    desired_size    = 4
    min_size        = 0
    max_size        = 6
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
  "uniquecr.azurecr.io",
  "uniquecr",
  "quay.io",
]

