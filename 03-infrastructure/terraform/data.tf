# AWS account and region data sources
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# AWS Organizations (for organization-level conditions in cross-account roles)
data "aws_organizations_organization" "current" {}

# Availability zones
data "aws_availability_zones" "available" {
  state = "available"
}


