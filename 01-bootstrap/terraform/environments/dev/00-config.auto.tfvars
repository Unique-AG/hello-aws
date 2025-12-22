# Environment-specific configuration
# Common values (aws_region, aws_account_id, org, org_moniker, client, client_name, semantic_version, deployed_at)
# are loaded from ../../common.auto.tfvars
#
# Default values (enable_* flags, etc.) are defined in variables.tf
# Only environment-specific overrides are defined here

environment = "dev"

# Retention Configuration (overridden for fast teardown in dev)
# Defaults are 30 days - override with 0 days for immediate deletion, 7 days for logs
kms_deletion_window           = 0
cloudwatch_log_retention_days = 7

