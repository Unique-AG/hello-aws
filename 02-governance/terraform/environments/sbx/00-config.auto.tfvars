# Environment-specific configuration
# Common values (aws_region, aws_account_id, org, org_moniker, product, product_moniker, semantic_version)
# are loaded from ../../common.auto.tfvars
#
# Default values are defined in variables.tf
# Only environment-specific overrides are defined here

environment = "sbx"

# Budget configuration (environment-specific)
# Lower budget for sandbox environment (cost optimization)
budget_amount         = 500
budget_contact_emails = []
