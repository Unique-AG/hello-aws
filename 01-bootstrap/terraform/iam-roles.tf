data "aws_iam_policy_document" "github_actions_assume_role" {
  count = var.use_oidc && var.github_repository != "" ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  count = var.use_oidc && var.github_repository != "" ? 1 : 0

  name = local.github_actions_role_name

  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role[0].json

  tags = merge(
    local.tags,
    {
      Name        = local.github_actions_role_name
      Description = "IAM role for GitHub Actions OIDC"
    }
  )
}

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
