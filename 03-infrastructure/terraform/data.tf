# AWS account and region data sources
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# AWS Organizations (for organization-level conditions in cross-account roles).
# Gated to match `aws_iam_role.connectivity_account`'s count — DescribeOrganization
# only succeeds from the org master account, so reading unconditionally 403s on
# member accounts (including the sandbox where the role isn't even created).
data "aws_organizations_organization" "current" {
  count = var.enable_connectivity_account_role && var.connectivity_account_id != null ? 1 : 0
}

# Availability zones
data "aws_availability_zones" "available" {
  state = "available"
}


