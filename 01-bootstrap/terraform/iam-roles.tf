#######################################
# Authentication Policy
#######################################
#
# AWS SSO (AWS IAM Identity Center) is the only permitted authentication
# mechanism for human access to AWS resources in this project.
#
# All interactive access must use AWS SSO. Long-lived credentials (access keys)
# are not permitted for human users. Service-to-service authentication uses
# IAM roles with temporary credentials.
#
#######################################

# IAM role for GitHub Actions OIDC
resource "aws_iam_role" "github_actions" {
  count = var.use_oidc && var.github_repository != "" ? 1 : 0

  name = local.github_actions_role_name

  assume_role_policy = templatefile("${path.module}/policies/github-actions-assume-role.json", {
    oidc_provider_arn = aws_iam_openid_connect_provider.github[0].arn
    github_repository = var.github_repository
  })

  tags = merge(
    local.tags,
    {
      Name        = local.github_actions_role_name
      Description = "IAM role for GitHub Actions OIDC"
    }
  )
}

# OIDC provider for GitHub Actions
resource "aws_iam_openid_connect_provider" "github" {
  count = var.use_oidc && var.github_repository != "" ? 1 : 0

  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]

  tags = merge(
    local.tags,
    {
      Name = "github-actions-oidc"
    }
  )
}

