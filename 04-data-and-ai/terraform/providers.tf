provider "aws" {
  region              = var.aws_region
  allowed_account_ids = var.aws_account_id != null ? [var.aws_account_id] : null

  default_tags {
    tags = local.tags
  }
}
