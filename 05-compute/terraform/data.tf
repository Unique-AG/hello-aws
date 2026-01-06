# AWS account and region data sources
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# AWS Organizations data source for organization-level conditions
data "aws_organizations_organization" "current" {}

# Availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Remote state from infrastructure layer
# Reads infrastructure layer outputs from Terraform state
data "terraform_remote_state" "infrastructure" {
  backend = "s3"

  config = {
    bucket       = coalesce(var.terraform_state_bucket, local.terraform_state_bucket)
    key          = "infrastructure/terraform.tfstate"
    region       = var.aws_region
    use_lockfile = true
    encrypt      = true
    kms_key_id   = coalesce(var.terraform_state_kms_key_id, local.terraform_state_kms_key_id)
  }
}

