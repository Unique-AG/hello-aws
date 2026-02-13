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
eks_node_group_instance_types = ["m6i.2xlarge"]
eks_node_group_desired_size   = 1
eks_node_group_min_size       = 1
eks_node_group_max_size       = 2

# ECR Pull-Through Cache
ecr_pull_through_cache_upstream_registries = [
  "public.ecr.aws",
  "uniquecr.azurecr.io",
  "uniquecr",
]

# ALB Configuration (disable deletion protection for sbx teardown)
alb_deletion_protection = false

# VPC Endpoints
enable_eks_endpoint = true

# CloudFront VPC Origin
kong_nlb_dns_name               = "ac8e021478e9d453ca330efeda9f65ee-c11e4236a635bb8c.elb.eu-central-2.amazonaws.com"
kong_nlb_security_group_id      = "sg-0ecdea019e21a09cb"
enable_cloudfront_vpc_origin    = true
internal_alb_certificate_domain = "*.sbx.rbcn.ai"
connectivity_account_id         = "198666613175"
