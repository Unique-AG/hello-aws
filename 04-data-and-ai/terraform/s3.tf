#######################################
# S3 Buckets
#######################################
#
# S3 buckets for data storage with:
# - KMS encryption using infrastructure layer key
# - Private access (no public access)
# - Versioning enabled
# - Access via S3 Gateway Endpoint (no internet required)
#######################################

# S3 Bucket for Application Data
resource "aws_s3_bucket" "application_data" {
  bucket = "s3-${module.naming.id}-application-data"

  tags = merge(
    local.tags,
    {
      Name    = "s3-${module.naming.id}-application-data"
      Purpose = "application-data"
    }
  )
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "application_data" {
  bucket = aws_s3_bucket.application_data.id

  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Server-Side Encryption
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

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "application_data" {
  bucket = aws_s3_bucket.application_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket Lifecycle Configuration (optional - can be customized)
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
  bucket = "s3-${module.naming.id}-ai-data"

  tags = merge(
    local.tags,
    {
      Name    = "s3-${module.naming.id}-ai-data"
      Purpose = "ai-data"
    }
  )
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "ai_data" {
  bucket = aws_s3_bucket.ai_data.id

  versioning_configuration {
    status = "Enabled"
  }
}

# S3 Bucket Server-Side Encryption
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

# S3 Bucket Public Access Block
resource "aws_s3_bucket_public_access_block" "ai_data" {
  bucket = aws_s3_bucket.ai_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket Policy for Bedrock Logging
resource "aws_s3_bucket_policy" "ai_data_bedrock" {
  bucket = aws_s3_bucket.ai_data.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockLogging"
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
        }
        Action = "s3:PutObject"
        Resource = "${aws_s3_bucket.ai_data.arn}/bedrock-logs/AWSLogs/${data.aws_caller_identity.current.account_id}/BedrockModelInvocationLogs/${data.aws_region.current.name}/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:aws:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.ai_data]
}

