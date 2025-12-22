# Environment-specific configuration
# Common values (aws_region, aws_account_id, org, org_moniker, client, client_name, semantic_version, deployed_at)
# are loaded from ../../common.auto.tfvars
#
# Default values are defined in variables.tf
# Only environment-specific overrides are defined here

environment = "sbx"

# Budget configuration (environment-specific)
# Lower budget for sandbox environment (cost optimization)
budget_amount         = 500
budget_contact_emails = ["support@unique.ch"]

# AWS Config Rules configuration
# Note: AWS Config service should be enabled at the organization/landing zone level
# Disabled for sandbox to reduce costs
enable_config_rules = false
config_rules        = []

