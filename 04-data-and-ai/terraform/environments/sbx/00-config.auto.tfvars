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

# Secrets Configuration (overridden for fast teardown in sandbox)
secrets_recovery_window_days = 0 # Immediate deletion for fast teardown

# Aurora Configuration (sandbox-specific)
aurora_instance_class      = "db.t4g.medium" # Smallest burstable instance
aurora_instance_count      = 1               # Single instance for sandbox
aurora_deletion_protection = false
aurora_skip_final_snapshot = true

# ElastiCache Configuration (sandbox-specific)
elasticache_node_type                  = "cache.t3.micro" # Smallest burstable in eu-central-2
elasticache_num_cache_nodes            = 1                # Single node for sandbox
elasticache_automatic_failover_enabled = false
elasticache_multi_az_enabled           = false
elasticache_snapshot_retention_limit   = 1 # Shorter retention for sandbox

# Disable Grafana (not available in eu-central-2)
enable_managed_grafana = false

# Disable Bedrock logging (requires KMS key policy update)
enable_bedrock_logging = false

# VPC Endpoints Configuration
# Required for EKS pods to access data and AI services without internet access
enable_rds_endpoint         = true # Required for RDS API operations from pods
enable_elasticache_endpoint = true # Required for ElastiCache API operations from pods

