# AWS account and region data sources
data "aws_caller_identity" "current" {}


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

# Remote state from data-and-ai layer
# Reads data-and-ai layer outputs (Prometheus workspace, observability S3 bucket)
data "terraform_remote_state" "data_and_ai" {
  backend = "s3"

  config = {
    bucket       = coalesce(var.terraform_state_bucket, local.terraform_state_bucket)
    key          = "data-and-ai/terraform.tfstate"
    region       = var.aws_region
    use_lockfile = true
    encrypt      = true
    kms_key_id   = coalesce(var.terraform_state_kms_key_id, local.terraform_state_kms_key_id)
  }
}

