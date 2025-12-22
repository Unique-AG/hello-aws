# Environment-specific configuration
# Common values (aws_region, aws_account_id, org, org_moniker, client, client_name, semantic_version, deployed_at)
# are loaded from ../../common.auto.tfvars
#
# Default values (enable_* flags, retention, etc.) are defined in variables.tf
# Only environment-specific overrides are defined here

environment = "prod"

# Retention uses defaults from variables.tf (30 days for KMS, 30 days for CloudWatch logs)
