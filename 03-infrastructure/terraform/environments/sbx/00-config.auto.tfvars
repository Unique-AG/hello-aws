# Environment-specific configuration
# Common values (aws_region, aws_account_id, org, org_moniker, product, product_moniker, semantic_version)
# are loaded from ../../common.auto.tfvars
#
# Default values (enable_* flags, DNS settings, etc.) are defined in variables.tf
# Only environment-specific overrides are defined here

environment = "sbx"

# AZ Configuration (2 AZs required for Aurora DB subnet group)
availability_zone_count = 2

# NAT Gateway Configuration (single NAT for sandbox)
single_nat_gateway = true

# Terraform State Configuration (from bootstrap layer)
# These are computed dynamically from naming module (same as bootstrap layer)
# Format: s3-{id_short}-tfstate (e.g., s3-uq-dogfood-x-euc2-tfstate)
# Format: alias/kms-{id}-tfstate (e.g., alias/kms-uq-dogfood-sbx-euc2-tfstate)
# Uncomment and set manually if you need to override the computed values:
# terraform_state_bucket     = ""
# terraform_state_kms_key_id = ""

# VPC Configuration (environment-specific)
# Using different CIDR to avoid conflicts with other environments
vpc_cidr = "10.1.0.0/19"

# Retention Configuration (overridden for fast teardown in sandbox)
# Defaults are 30 days - override with 0 days for immediate deletion, 7 days for logs
kms_deletion_window           = 0
cloudwatch_log_retention_days = 7

# Bastion and Management Server Configuration (sandbox environment)
ssm_endpoints_enabled            = true
management_server_enabled        = true
management_server_public_access = false       # Use Session Manager for access
management_server_instance_type = "t3.medium" # Upgraded from t3.micro for better performance (4 GB RAM vs 1 GB)
management_server_disk_size     = 30
management_server_monitoring    = false

# GitHub Runners
github_runners_enabled = true

# Secondary CIDR for EKS pod networking
secondary_cidr_enabled = true

# Route 53 Private Hosted Zone Configuration
# Associates this VPC with the Route 53 Private Hosted Zone from landing zone
# This enables DNS resolution across all VPCs associated with the zone
# Uncomment and set to your hosted zone values before deploying:
# route53_private_zone_domain = "sbx.example.com"
# route53_private_zone_id     = "ZXXXXXXXXXXXXXXXXX"

