#######################################
# S3 Buckets
#######################################
#
# S3 buckets for data storage with:
# - KMS encryption using infrastructure layer key
# - Private access (no public access)
# - Versioning enabled
# - VPC-only access enforced via bucket policy (S3 Gateway Endpoint required)
# - Exception: Bedrock service can write logs (ai_data bucket only)
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

# S3 Bucket Policy: VPC-Only Access
# Restricts data access to only the VPC Gateway Endpoint (internal-only)
# Denies data operations unless they come from the VPC Gateway Endpoint
# Note: Management operations (GetBucketPolicy, PutBucketPolicy, etc.) are not denied
# to allow Terraform and IAM users to manage the bucket policy itself
resource "aws_s3_bucket_policy" "application_data_vpc_only" {
  count = local.infrastructure.s3_gateway_endpoint_id != null ? 1 : 0

  bucket = aws_s3_bucket.application_data.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyDataAccessExceptVpcEndpoint"
        Effect = "Deny"
        Principal = "*"
        # Only deny data operations, not management operations
        # This allows Terraform and IAM users to manage bucket policies
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetObjectVersion",
          "s3:DeleteObjectVersion",
          "s3:RestoreObject",
          "s3:GetObjectAcl",
          "s3:PutObjectAcl"
        ]
        Resource = [
          aws_s3_bucket.application_data.arn,
          "${aws_s3_bucket.application_data.arn}/*"
        ]
        Condition = {
          # Deny if SourceVpce exists but doesn't match our endpoint
          # OR if SourceVpce doesn't exist (external access without endpoint)
          # This ensures only VPC endpoint access is allowed for data operations
          StringNotEquals = {
            "aws:SourceVpce" = local.infrastructure.s3_gateway_endpoint_id
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.application_data]
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

# S3 Bucket Policy: VPC-Only Access
# Restricts data access to only the VPC Gateway Endpoint (internal-only)
# Denies data operations unless they come from the VPC Gateway Endpoint
# Bedrock logging is configured to use CloudWatch Logs instead of S3
# Note: Management operations (GetBucketPolicy, PutBucketPolicy, etc.) are not denied
# to allow Terraform and IAM users to manage the bucket policy itself
#
# Reference: https://docs.aws.amazon.com/AmazonS3/latest/userguide/example-bucket-policies-vpc-endpoint.html
resource "aws_s3_bucket_policy" "ai_data_vpc_only" {
  count = local.infrastructure.s3_gateway_endpoint_id != null ? 1 : 0

  bucket = aws_s3_bucket.ai_data.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyDataAccessExceptVpcEndpoint"
        Effect = "Deny"
        Principal = "*"
        # Only deny data operations, not management operations
        # This allows Terraform and IAM users to manage bucket policies
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetObjectVersion",
          "s3:DeleteObjectVersion",
          "s3:RestoreObject",
          "s3:GetObjectAcl",
          "s3:PutObjectAcl"
        ]
        Resource = [
          aws_s3_bucket.ai_data.arn,
          "${aws_s3_bucket.ai_data.arn}/*"
        ]
        Condition = {
          # Deny if SourceVpce exists but doesn't match our endpoint
          # OR if SourceVpce doesn't exist (external access without endpoint)
          # This ensures only VPC endpoint access is allowed for data operations
          StringNotEquals = {
            "aws:SourceVpce" = local.infrastructure.s3_gateway_endpoint_id
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.ai_data]
}

