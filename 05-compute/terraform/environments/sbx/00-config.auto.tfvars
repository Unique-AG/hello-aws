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
eks_cluster_version            = "1.35"
eks_endpoint_private_access    = true
eks_cluster_log_retention_days = 7

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

  # Conduct sandbox hosts. The sandbox workload itself runs in a per-sandbox
  # peer-pod EC2 instance, so these nodes only carry the kata shim and the
  # adaptor -- they do not need to be large.
  #
  # Tainted so nothing but sandbox components lands here. Deliberately no
  # startup taint: EKS reconciles managed node group taints, so one removed by
  # kata-deploy would simply be re-applied. The scheduling race is closed on
  # the RuntimeClass instead, which selects the node label kata-deploy sets
  # once the shim is in place.
  sandbox = {
    instance_types = ["m6i.large"]
    desired_size   = 1
    min_size       = 0
    max_size       = 3
    labels = {
      lifecycle   = "ephemeral"
      scalability = "rapid"
      workload    = "sandbox"
    }
    taints = [
      { key = "workload", value = "sandbox", effect = "NO_SCHEDULE" }
    ]
  }
}

# ECR Pull-Through Cache
ecr_pull_through_cache_upstream_registries = [
  "public.ecr.aws",
  # ACR upstream for Unique application images: the full registry hostname and
  # its short alias, both of which must exactly match `acr_registry_url` (and
  # the alias derived from it) in the repository-root common.auto.tfvars --
  # entries that do not match are silently dropped by the `contains(...)`
  # filter in ../../ecr.tf, leaving the cluster unable to pull app images.
  #
  # 06-applications/scripts/configure-instance.sh rewrites both these entries
  # and `acr_registry_url` from instance-config.yaml (aws.ecr.primary.prefix).
  # Do not delete them when de-configuring: a fresh clone would then have no
  # way to restore its ACR pull-through cache.
  "example.azurecr.io",
  "example",
  "quay.io",
  "registry.k8s.io",
]

