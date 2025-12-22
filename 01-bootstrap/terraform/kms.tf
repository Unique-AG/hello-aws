# KMS key for encrypting Terraform state
resource "aws_kms_key" "terraform_state" {
  count = var.enable_server_side_encryption ? 1 : 0

  description = "KMS key for encrypting Terraform state in ${var.environment} environment"
  # AWS requires minimum 7 days - enforce when 0 is specified (for fast teardown in dev/sbx)
  deletion_window_in_days = var.kms_deletion_window == 0 ? 7 : var.kms_deletion_window
  enable_key_rotation     = true

  # Note: KMS policy kept inline due to complex conditional logic for GitHub Actions role
  # The policy structure dynamically includes/excludes statements based on OIDC configuration
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid    = "Enable IAM User Permissions"
          Effect = "Allow"
          Principal = {
            AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
          }
          Action   = "kms:*"
          Resource = "*"
        },
        {
          Sid    = "Allow S3 to use the key"
          Effect = "Allow"
          Principal = {
            Service = "s3.amazonaws.com"
          }
          Action = [
            "kms:Decrypt",
            "kms:GenerateDataKey"
          ]
          Resource = "*"
          Condition = {
            StringEquals = {
              "kms:ViaService" = "s3.${data.aws_region.current.name}.amazonaws.com"
            }
          }
        },
        {
          Sid    = "Allow CloudWatch Logs to use the key"
          Effect = "Allow"
          Principal = {
            Service = "logs.${data.aws_region.current.name}.amazonaws.com"
          }
          Action = [
            "kms:Encrypt",
            "kms:Decrypt",
            "kms:ReEncrypt*",
            "kms:GenerateDataKey*",
            "kms:DescribeKey"
          ]
          Resource = "*"
          Condition = {
            ArnEquals = {
              "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
            }
          }
        }
      ],
      var.use_oidc && var.github_repository != "" ? [
        {
          Sid    = "Allow GitHub Actions role to use the key"
          Effect = "Allow"
          Principal = {
            AWS = aws_iam_role.github_actions[0].arn
          }
          Action = [
            "kms:Decrypt",
            "kms:GenerateDataKey",
            "kms:DescribeKey"
          ]
          Resource = "*"
        }
      ] : []
    )
  })

  tags = merge(
    local.tags,
    {
      Name        = local.kms_key_alias
      Description = "KMS key for Terraform state encryption"
    }
  )
}

# KMS key alias
resource "aws_kms_alias" "terraform_state" {
  count         = var.enable_server_side_encryption ? 1 : 0
  name          = local.kms_key_alias # Already includes "alias/" prefix
  target_key_id = aws_kms_key.terraform_state[0].key_id
}

