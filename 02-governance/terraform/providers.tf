provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }
}


# Quota requests are mirrored into the recovery Region (CA 16.3/16.4). Where the
# installation has no pair, this aliases the home Region and creates nothing.
provider "aws" {
  alias  = "recovery"
  region = coalesce(local.quota_recovery_region, var.aws_region)

  default_tags {
    tags = local.tags
  }
}
