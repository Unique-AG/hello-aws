resource "random_string" "s3_suffix" {
  length  = 8
  special = false
  upper   = false
}

# S3 Bucket for Application Data
resource "aws_s3_bucket" "application_data" {
  bucket = "s3-${module.naming.id}-application-data-${random_string.s3_suffix.result}"

  tags = {
    Name    = "s3-${module.naming.id}-application-data-${random_string.s3_suffix.result}"
    Purpose = "application-data"
  }
}

resource "aws_s3_bucket_versioning" "application_data" {
  bucket = aws_s3_bucket.application_data.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "application_data" {
  bucket = aws_s3_bucket.application_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = local.infrastructure.kms_key_general_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "application_data" {
  bucket = aws_s3_bucket.application_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# VPC-only access — denies data operations unless via S3 Gateway Endpoint
# Management operations (GetBucketPolicy, etc.) are not denied to allow Terraform access
data "aws_iam_policy_document" "application_data_vpc_only" {
  count = local.infrastructure.s3_gateway_endpoint_id != null ? 1 : 0

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
      "s3:RestoreObject",
      "s3:GetObjectAcl",
      "s3:PutObjectAcl",
    ]

    resources = [
      aws_s3_bucket.application_data.arn,
      "${aws_s3_bucket.application_data.arn}/*",
    ]

    condition {
      test     = "StringNotEquals"
      variable = "aws:SourceVpce"
      values   = [local.infrastructure.s3_gateway_endpoint_id]
    }
  }
}

resource "aws_s3_bucket_policy" "application_data_vpc_only" {
  count = local.infrastructure.s3_gateway_endpoint_id != null ? 1 : 0

  bucket = aws_s3_bucket.application_data.id
  policy = data.aws_iam_policy_document.application_data_vpc_only[0].json

  depends_on = [aws_s3_bucket_public_access_block.application_data]
}

# Lifecycle — transition to cheaper storage classes
resource "aws_s3_bucket_lifecycle_configuration" "application_data" {
  bucket = aws_s3_bucket.application_data.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }

  rule {
    id     = "transition-to-glacier"
    status = "Enabled"

    filter {}

    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
}

# S3 Bucket for AI/ML Data
resource "aws_s3_bucket" "ai_data" {
  bucket = "s3-${module.naming.id}-ai-data-${random_string.s3_suffix.result}"

  tags = {
    Name    = "s3-${module.naming.id}-ai-data-${random_string.s3_suffix.result}"
    Purpose = "ai-data"
  }
}

resource "aws_s3_bucket_versioning" "ai_data" {
  bucket = aws_s3_bucket.ai_data.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ai_data" {
  bucket = aws_s3_bucket.ai_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = local.infrastructure.kms_key_general_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "ai_data" {
  bucket = aws_s3_bucket.ai_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# VPC-only access — same policy as application_data bucket
data "aws_iam_policy_document" "ai_data_vpc_only" {
  count = local.infrastructure.s3_gateway_endpoint_id != null ? 1 : 0

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
      "s3:RestoreObject",
      "s3:GetObjectAcl",
      "s3:PutObjectAcl",
    ]

    resources = [
      aws_s3_bucket.ai_data.arn,
      "${aws_s3_bucket.ai_data.arn}/*",
    ]

    condition {
      test     = "StringNotEquals"
      variable = "aws:SourceVpce"
      values   = [local.infrastructure.s3_gateway_endpoint_id]
    }
  }
}

resource "aws_s3_bucket_policy" "ai_data_vpc_only" {
  count = local.infrastructure.s3_gateway_endpoint_id != null ? 1 : 0

  bucket = aws_s3_bucket.ai_data.id
  policy = data.aws_iam_policy_document.ai_data_vpc_only[0].json

  depends_on = [aws_s3_bucket_public_access_block.ai_data]
}
