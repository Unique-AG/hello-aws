# AWS account and region data sources
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# AWS Organizations (for organization-level conditions in cross-account roles)
data "aws_organizations_organization" "current" {}

# Availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Remote state from bootstrap layer
# Reads bootstrap layer outputs from Terraform state
# Note: Backend configuration still requires manual bootstrap outputs for initialization
# This remote state is for consistency and any future uses of bootstrap outputs
data "terraform_remote_state" "bootstrap" {
  backend = "s3"

  config = {
    bucket       = coalesce(var.terraform_state_bucket, local.terraform_state_bucket)
    key          = "bootstrap/terraform.tfstate"
    region       = var.aws_region
    encrypt      = true
    kms_key_id   = coalesce(var.terraform_state_kms_key_id, local.terraform_state_kms_key_id)
    use_lockfile = true
  }
}

