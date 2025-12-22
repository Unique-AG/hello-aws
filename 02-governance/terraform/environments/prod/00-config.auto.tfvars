# Environment-specific configuration
# Common values (aws_region, aws_account_id, org, org_moniker, client, client_name, semantic_version, deployed_at)
# are loaded from ../../common.auto.tfvars
#
# Default values are defined in variables.tf
# Only environment-specific overrides are defined here

environment = "prod"

# Budget configuration (environment-specific)
budget_amount         = 5000
budget_contact_emails = ["support@unique.ch", "finance@unique.ch"]

# AWS Config Rules configuration
# Note: AWS Config service should be enabled at the organization/landing zone level
enable_config_rules = false
config_rules        = []

