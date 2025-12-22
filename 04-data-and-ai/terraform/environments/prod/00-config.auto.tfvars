# Environment-specific configuration
# Common values (aws_region, aws_account_id, org, org_moniker, client, client_name, semantic_version, deployed_at)
# are loaded from ../../common.auto.tfvars
#
# Default values (enable_* flags, etc.) are defined in variables.tf
# Only environment-specific overrides are defined here

environment = "prod"

# Terraform State Configuration (from bootstrap layer)
# These are required to access remote state from infrastructure layer
terraform_state_bucket         = "" # Set from bootstrap layer output: s3_bucket_name
terraform_state_dynamodb_table = "" # Set from bootstrap layer output: dynamodb_table_name
terraform_state_kms_key_id     = "" # Set from bootstrap layer output: kms_key_alias or kms_key_arn

# Aurora Configuration (prod-specific)
aurora_backup_retention_period = 30 # Longer retention for production
aurora_deletion_protection     = true
aurora_skip_final_snapshot     = false

# ElastiCache Configuration (prod-specific)
elasticache_snapshot_retention_limit = 14 # Longer retention for production

