# General Encryption Key
# Used for: EKS secrets, EBS volumes, S3, RDS, ElastiCache, ECR
resource "aws_kms_key" "general" {
  description = "KMS key for general encryption (EKS, EBS, S3, RDS, ElastiCache, ECR)"
  # AWS requires minimum 7 days - enforce when 0 is specified (for fast teardown in dev/sbx)
  deletion_window_in_days = var.kms_deletion_window == 0 ? 7 : var.kms_deletion_window
  enable_key_rotation     = var.kms_enable_rotation

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
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
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      },
      {
        Sid    = "Allow EKS"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow EC2"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource = "*"
        Condition = {
          Bool = { "kms:GrantIsForAWSResource" = "true" }
        }
      },
      {
        Sid    = "Allow RDS"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource = "*"
        Condition = {
          Bool = { "kms:GrantIsForAWSResource" = "true" }
        }
      },
      {
        Sid    = "Allow ElastiCache"
        Effect = "Allow"
        Principal = {
          Service = "elasticache.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow S3"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow ECR"
        Effect = "Allow"
        Principal = {
          Service = "ecr.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow SNS"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(
    local.tags,
    {
      Name    = "kms-${module.naming.id}-general"
      Purpose = "general-encryption"
    }
  )
}

resource "aws_kms_alias" "general" {
  name          = "alias/kms-${module.naming.id}-general"
  target_key_id = aws_kms_key.general.key_id
}

# Secrets Manager Encryption Key
# Used for: Secrets Manager secrets encryption
resource "aws_kms_key" "secrets_manager" {
  description = "KMS key for Secrets Manager encryption"
  # AWS requires minimum 7 days - enforce when 0 is specified (for fast teardown in dev/sbx)
  deletion_window_in_days = var.kms_deletion_window == 0 ? 7 : var.kms_deletion_window
  enable_key_rotation     = var.kms_enable_rotation

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
        Sid    = "Allow Secrets Manager"
        Effect = "Allow"
        Principal = {
          Service = "secretsmanager.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow ECR Pull Through Cache"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/pullthroughcache.ecr.amazonaws.com/AWSServiceRoleForECRPullThroughCache"
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(
    local.tags,
    {
      Name    = "kms-${module.naming.id}-secrets-manager"
      Purpose = "secrets-manager"
    }
  )
}

resource "aws_kms_alias" "secrets_manager" {
  name          = "alias/kms-${module.naming.id}-secrets-manager"
  target_key_id = aws_kms_key.secrets_manager.key_id
}

# CloudWatch Logs Encryption Key
# Used for: CloudWatch Log Groups encryption
resource "aws_kms_key" "cloudwatch_logs" {
  description = "KMS key for CloudWatch Logs encryption"
  # AWS requires minimum 7 days - enforce when 0 is specified (for fast teardown in dev/sbx)
  deletion_window_in_days = var.kms_deletion_window == 0 ? 7 : var.kms_deletion_window
  enable_key_rotation     = var.kms_enable_rotation

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
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
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      }
    ]
  })

  tags = merge(
    local.tags,
    {
      Name    = "kms-${module.naming.id}-cloudwatch-logs"
      Purpose = "cloudwatch-logs"
    }
  )
}

resource "aws_kms_alias" "cloudwatch_logs" {
  name          = "alias/kms-${module.naming.id}-cloudwatch-logs"
  target_key_id = aws_kms_key.cloudwatch_logs.key_id
}

# Managed Prometheus Encryption Key
# Used for: Managed Prometheus workspace encryption
resource "aws_kms_key" "prometheus" {
  count = var.enable_managed_prometheus ? 1 : 0

  description = "KMS key for Managed Prometheus workspace encryption"
  # AWS requires minimum 7 days - enforce when 0 is specified (for fast teardown in dev/sbx)
  deletion_window_in_days = var.kms_deletion_window == 0 ? 7 : var.kms_deletion_window
  enable_key_rotation     = var.kms_enable_rotation

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
        Sid    = "Allow Prometheus Service"
        Effect = "Allow"
        Principal = {
          Service = "aps.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(
    local.tags,
    {
      Name    = "kms-${module.naming.id}-prometheus"
      Purpose = "prometheus"
    }
  )
}

resource "aws_kms_alias" "prometheus" {
  count         = var.enable_managed_prometheus ? 1 : 0
  name          = "alias/kms-${module.naming.id}-prometheus"
  target_key_id = aws_kms_key.prometheus[0].key_id
}

# EBS Encryption by Default
# Ensures all new EBS volumes are encrypted automatically
resource "aws_ebs_encryption_by_default" "main" {
  enabled = true
}

resource "aws_ebs_default_kms_key" "main" {
  key_arn = aws_kms_key.general.arn
}
