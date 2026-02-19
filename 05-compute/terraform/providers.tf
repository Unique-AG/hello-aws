provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }
}

# us-east-1 provider for CloudFront VPC Origin RAM sharing
# CloudFront VPC Origins are global resources - RAM sharing must be in us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.tags
  }
}

