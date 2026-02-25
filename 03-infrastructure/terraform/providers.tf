provider "aws" {
  region              = var.aws_region
  allowed_account_ids = var.aws_account_id != null ? [var.aws_account_id] : null

  default_tags {
    tags = local.tags
  }
}

# Required for CloudFront VPC Origin RAM sharing (global resources must use us-east-1)
provider "aws" {
  alias               = "us_east_1"
  region              = "us-east-1"
  allowed_account_ids = var.aws_account_id != null ? [var.aws_account_id] : null

  default_tags {
    tags = local.tags
  }
}
