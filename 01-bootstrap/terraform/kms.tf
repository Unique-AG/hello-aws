data "aws_iam_policy_document" "kms_terraform_state" {
  # checkov:skip=CKV_AWS_109:KMS key policy - root account needs permissions management to prevent lockout
  # checkov:skip=CKV_AWS_111:KMS key policy - root account needs write access to manage key lifecycle
  # checkov:skip=CKV_AWS_356:KMS key policy - resources=* is self-referential (means this key only)
  statement {
    sid       = "EnableIAMUserPermissions"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid    = "AllowS3ToUseTheKey"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${data.aws_region.current.name}.amazonaws.com"]
    }
  }

  statement {
    sid    = "AllowCloudWatchLogsToUseTheKey"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.name}.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }

  dynamic "statement" {
    for_each = var.use_oidc && var.github_repository != "" ? [1] : []
    content {
      sid    = "AllowGitHubActionsRoleToUseTheKey"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey",
      ]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = [aws_iam_role.github_actions[0].arn]
      }
    }
  }
}

resource "aws_kms_key" "terraform_state" {
  count = var.enable_server_side_encryption ? 1 : 0

  description = "KMS key for encrypting Terraform state in ${var.environment} environment"
  # AWS requires minimum 7 days — enforce when 0 is specified (for fast teardown in dev/sbx)
  deletion_window_in_days = var.kms_deletion_window == 0 ? 7 : var.kms_deletion_window
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_terraform_state.json

  tags = merge(
    local.tags,
    {
      Name        = local.kms_key_alias
      Description = "KMS key for Terraform state encryption"
    }
  )
}

resource "aws_kms_alias" "terraform_state" {
  count         = var.enable_server_side_encryption ? 1 : 0
  name          = local.kms_key_alias # Already includes "alias/" prefix
  target_key_id = aws_kms_key.terraform_state[0].key_id
}
