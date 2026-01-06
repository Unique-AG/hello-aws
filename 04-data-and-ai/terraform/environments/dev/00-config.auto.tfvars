# Environment-specific configuration
# Common values (aws_region, aws_account_id, org, org_moniker, client, client_name, semantic_version, deployed_at)
# are loaded from ../../common.auto.tfvars
#
# Default values (enable_* flags, etc.) are defined in variables.tf
# Only environment-specific overrides are defined here

environment = "dev"

# Terraform State Configuration (from bootstrap layer)
# These are required to access remote state from infrastructure layer
terraform_state_bucket         = "" # Set from bootstrap layer output: s3_bucket_name
terraform_state_dynamodb_table = "" # Set from bootstrap layer output: dynamodb_table_name
terraform_state_kms_key_id     = "" # Set from bootstrap layer output: kms_key_alias or kms_key_arn

# Secrets Configuration (overridden for fast teardown in dev)
secrets_recovery_window_days = 0 # Immediate deletion for fast teardown

# Aurora Configuration (dev-specific)
aurora_instance_class      = "db.r6g.medium" # Smaller instance for dev
aurora_instance_count      = 1               # Single instance for dev
aurora_deletion_protection = false
aurora_skip_final_snapshot = true

# ElastiCache Configuration (dev-specific)
elasticache_node_type                  = "cache.r7g.medium" # Smaller instance for dev
elasticache_num_cache_nodes            = 1                  # Single node for dev
elasticache_automatic_failover_enabled = false
elasticache_multi_az_enabled           = false
elasticache_snapshot_retention_limit   = 1 # Shorter retention for dev

