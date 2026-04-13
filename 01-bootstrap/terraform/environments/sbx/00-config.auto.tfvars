# Environment-specific configuration
# Common values (aws_region, aws_account_id, org, org_moniker, product, product_moniker, semantic_version)
# are loaded from ../../common.auto.tfvars
#
# Default values (enable_* flags, retention, etc.) are defined in variables.tf
# Only environment-specific overrides are defined here

environment = "sbx"

# GitHub OIDC Configuration
use_oidc          = true
github_repository = "Unique-AG/hello-aws"

# Retention Configuration (overridden for fast teardown in sandbox)
# Defaults are 30 days - override with 0 days for immediate deletion, 7 days for logs
kms_deletion_window           = 0
cloudwatch_log_retention_days = 7
