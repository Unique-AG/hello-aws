# Environment-specific configuration
# Common values (aws_region, aws_account_id, org, org_moniker, client, client_name, semantic_version, deployed_at)
# are loaded from ../../common.auto.tfvars
#
# Default values (enable_* flags, DNS settings, etc.) are defined in variables.tf
# Only environment-specific overrides are defined here

environment = "dev"

# Terraform State Configuration (from bootstrap layer)
# These are required for remote state access to bootstrap layer
# Also used for backend configuration during terraform init
terraform_state_bucket     = "" # Set from bootstrap layer output: s3_bucket_name
terraform_state_kms_key_id = "" # Set from bootstrap layer output: kms_key_alias or kms_key_arn

# VPC Configuration (environment-specific)
vpc_cidr = "10.0.0.0/16"

# Retention Configuration (overridden for fast teardown in dev)
# Defaults are 30 days - override with 0 days for immediate deletion, 7 days for logs
kms_deletion_window           = 0
cloudwatch_log_retention_days = 7

# Bastion and Management Server Configuration (dev environment)
enable_ssm_endpoints            = true
enable_management_server        = true
management_server_public_access = false # Use Session Manager for access
management_server_instance_type = "t3.micro"
management_server_disk_size     = 20
management_server_monitoring    = false

