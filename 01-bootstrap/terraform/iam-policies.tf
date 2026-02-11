data "aws_iam_policy_document" "github_actions_terraform_state" {
  count = var.use_oidc && var.github_repository != "" ? 1 : 0

  statement {
    sid    = "S3StateAccess"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
      "s3:DeleteObject",
    ]

    resources = [
      aws_s3_bucket.terraform_state.arn,
      "${aws_s3_bucket.terraform_state.arn}/*",
    ]
  }

  statement {
    sid    = "KMSStateEncryption"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]

    resources = [
      var.enable_server_side_encryption ? aws_kms_key.terraform_state[0].arn : "*",
    ]
  }
}

resource "aws_iam_role_policy" "github_actions_terraform" {
  count = var.use_oidc && var.github_repository != "" ? 1 : 0

  name = "${module.naming.iam_role_prefix}-terraform-state-access"
  role = aws_iam_role.github_actions[0].id

  policy = data.aws_iam_policy_document.github_actions_terraform_state[0].json
}
