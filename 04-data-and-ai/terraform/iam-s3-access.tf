# IAM user with static S3 credentials for the chat service
# The chat service's S3BucketStrategy requires explicit access keys rather than IRSA
# Access key is created by .scripts/seed-secrets.sh (not in Terraform to avoid secrets in state)

resource "aws_iam_user" "s3_access" {
  #checkov:skip=CKV_AWS_273: see docs/security-baseline.md
  name = "iam-user-${module.naming.id}-s3-access"
  path = "/service-accounts/"

  tags = {
    Name    = "iam-user-${module.naming.id}-s3-access"
    Purpose = "s3-programmatic-access"
  }
}

data "aws_iam_policy_document" "s3_access" {
  statement {
    sid    = "S3BucketAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetObjectVersion",
      "s3:DeleteObjectVersion",
    ]
    resources = [
      aws_s3_bucket.application_data.arn,
      "${aws_s3_bucket.application_data.arn}/*",
      aws_s3_bucket.ai_data.arn,
      "${aws_s3_bucket.ai_data.arn}/*",
    ]
  }

  statement {
    sid    = "KMSAccess"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:GenerateDataKey",
    ]
    resources = [local.infrastructure.kms_key_general_arn]
  }
}

resource "aws_iam_user_policy" "s3_access" {
  name   = "s3-bucket-access"
  user   = aws_iam_user.s3_access.name
  policy = data.aws_iam_policy_document.s3_access.json
}

# S3 Access Credential Containers in Secrets Manager
# Access key values populated by .scripts/seed-secrets.sh

resource "aws_secretsmanager_secret" "s3_access_key_id" {
  name                    = var.s3_access_key_id_secret_name
  description             = "S3 access key ID for programmatic access"
  recovery_window_in_days = var.secrets_recovery_window_days
  kms_key_id              = local.infrastructure.kms_key_secrets_manager_arn

  tags = { Name = var.s3_access_key_id_secret_name, Purpose = "s3-credentials" }
}

resource "aws_secretsmanager_secret" "s3_secret_access_key" {
  name                    = var.s3_secret_access_key_secret_name
  description             = "S3 secret access key for programmatic access"
  recovery_window_in_days = var.secrets_recovery_window_days
  kms_key_id              = local.infrastructure.kms_key_secrets_manager_arn

  tags = { Name = var.s3_secret_access_key_secret_name, Purpose = "s3-credentials" }
}

# S3 Config — infrastructure facts (Terraform-managed values)

resource "aws_secretsmanager_secret" "s3_endpoint" {
  name                    = var.s3_endpoint_secret_name
  description             = "S3 endpoint URL for programmatic access"
  recovery_window_in_days = var.secrets_recovery_window_days
  kms_key_id              = local.infrastructure.kms_key_secrets_manager_arn

  tags = { Name = var.s3_endpoint_secret_name, Purpose = "s3-config" }
}

resource "aws_secretsmanager_secret_version" "s3_endpoint" {
  secret_id     = aws_secretsmanager_secret.s3_endpoint.id
  secret_string = "https://s3.${var.aws_region}.amazonaws.com"
}

resource "aws_secretsmanager_secret" "s3_region" {
  name                    = var.s3_region_secret_name
  description             = "S3 region for programmatic access"
  recovery_window_in_days = var.secrets_recovery_window_days
  kms_key_id              = local.infrastructure.kms_key_secrets_manager_arn

  tags = { Name = var.s3_region_secret_name, Purpose = "s3-config" }
}

resource "aws_secretsmanager_secret_version" "s3_region" {
  secret_id     = aws_secretsmanager_secret.s3_region.id
  secret_string = var.aws_region
}
