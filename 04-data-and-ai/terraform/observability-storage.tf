# S3 Bucket for Observability Data (Loki logs, Tempo traces)
resource "aws_s3_bucket" "observability" {
  #checkov:skip=CKV_AWS_18: see docs/security-baseline.md
  #checkov:skip=CKV_AWS_144: see docs/security-baseline.md
  #checkov:skip=CKV2_AWS_62: see docs/security-baseline.md
  bucket        = "s3-${module.naming.id}-observability-${random_string.s3_suffix.result}"
  force_destroy = var.s3_force_destroy

  tags = merge(module.naming.tags, {
    Name    = "s3-${module.naming.id}-observability-${random_string.s3_suffix.result}"
    Purpose = "observability"
  })
}

resource "aws_s3_bucket_versioning" "observability" {
  bucket = aws_s3_bucket.observability.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "observability" {
  bucket = aws_s3_bucket.observability.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = local.infrastructure.kms_key_general_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "observability" {
  bucket = aws_s3_bucket.observability.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# VPC-only access — same pattern as application_data bucket
data "aws_iam_policy_document" "observability_vpc_only" {
  count = var.enable_s3_vpc_only_policy && local.infrastructure.s3_gateway_endpoint_id != null ? 1 : 0

  statement {
    sid    = "DenyDataAccessExceptVpcEndpoint"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetObjectVersion",
      "s3:DeleteObjectVersion",
    ]

    resources = [
      aws_s3_bucket.observability.arn,
      "${aws_s3_bucket.observability.arn}/*",
    ]

    condition {
      test     = "StringNotEquals"
      variable = "aws:SourceVpce"
      values   = [local.infrastructure.s3_gateway_endpoint_id]
    }
  }
}

resource "aws_s3_bucket_policy" "observability_vpc_only" {
  count = var.enable_s3_vpc_only_policy && local.infrastructure.s3_gateway_endpoint_id != null ? 1 : 0

  bucket = aws_s3_bucket.observability.id
  policy = data.aws_iam_policy_document.observability_vpc_only[0].json

  depends_on = [aws_s3_bucket_public_access_block.observability]
}

# Lifecycle — transition logs/traces to cheaper storage, expire after 1 year
resource "aws_s3_bucket_lifecycle_configuration" "observability" {
  bucket = aws_s3_bucket.observability.id

  rule {
    id     = "loki-lifecycle"
    status = "Enabled"

    filter {
      prefix = "loki/"
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }

  rule {
    id     = "tempo-lifecycle"
    status = "Enabled"

    filter {
      prefix = "tempo/"
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 90
    }
  }

  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Store bucket name in Secrets Manager for ExternalSecrets access
resource "aws_secretsmanager_secret" "s3_observability_bucket" {
  #checkov:skip=CKV2_AWS_57: see docs/security-baseline.md
  name                    = "s3-observability-bucket"
  description             = "S3 bucket name for observability data (Loki, Tempo)"
  recovery_window_in_days = var.secrets_recovery_window_days
  kms_key_id              = local.infrastructure.kms_key_secrets_manager_arn

  tags = { Name = "s3-observability-bucket", Purpose = "s3-config" }
}

resource "aws_secretsmanager_secret_version" "s3_observability_bucket" {
  secret_id     = aws_secretsmanager_secret.s3_observability_bucket.id
  secret_string = aws_s3_bucket.observability.id
}
