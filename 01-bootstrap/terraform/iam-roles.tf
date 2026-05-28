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

    # Narrow the OIDC subject claim from "any context" (StringLike with :*) to
    # an explicit allowlist of refs/events. Reduces blast radius of a stolen
    # or forged OIDC token — only push to deploy/sbx, push to main, and
    # pull_request events can assume this role.
    #
    # Format reference:
    # https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect#example-subject-claims
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repository}:ref:refs/heads/deploy/sbx",
        "repo:${var.github_repository}:ref:refs/heads/main",
        "repo:${var.github_repository}:pull_request",
      ]
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

data "tls_certificate" "github_actions" {
  count = var.use_oidc && var.github_repository != "" ? 1 : 0

  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.use_oidc && var.github_repository != "" ? 1 : 0

  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [data.tls_certificate.github_actions[0].certificates[0].sha1_fingerprint]

  tags = merge(
    local.tags,
    {
      Name = "github-actions-oidc"
    }
  )
}
