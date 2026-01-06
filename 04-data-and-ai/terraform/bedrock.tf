#######################################
# Amazon Bedrock
#######################################
#
# Amazon Bedrock foundation model access with:
# - Private access via VPC endpoint
# - Model invocation logging to CloudWatch Logs
# - Access via Bedrock Interface Endpoint (no internet required)
#
# Model Access Control:
# To restrict models, use an SCP with NotResource pattern:
# https://aws.amazon.com/blogs/security/unlock-new-possibilities-aws-organizations-service-control-policy-now-supports-full-iam-language/
#
# Example SCP to allow only Amazon models:
# {
#   "Version": "2012-10-17",
#   "Statement": [
#     {
#       "Effect": "Allow",
#       "Action": "bedrock:*",
#       "Resource": "*"
#     },
#     {
#       "Effect": "Deny",
#       "Action": [
#         "bedrock:InvokeModel",
#         "bedrock:InvokeModelWithResponseStream",
#         "bedrock:PutFoundationModelEntitlement"
#       ],
#       "NotResource": [
#         "arn:aws:bedrock:*::foundation-model/amazon.*",
#         "arn:aws:bedrock:*::foundation-model/anthropic.*"
#       ]
#     }
#   ]
# }
#######################################

# CloudWatch Log Group for Bedrock Model Invocation Logs
resource "aws_cloudwatch_log_group" "bedrock_logs" {
  count = var.enable_bedrock_logging ? 1 : 0

  name              = "/${var.org_moniker}/${var.client}/${var.environment}/bedrock/model-invocations"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = local.infrastructure.kms_key_cloudwatch_logs_arn

  tags = merge(
    local.tags,
    {
      Name    = "log-${module.naming.id}-bedrock"
      Purpose = "bedrock-model-invocation-logs"
    }
  )
}

# IAM Role for Bedrock to Write to CloudWatch Logs
resource "aws_iam_role" "bedrock_logging" {
  count = var.enable_bedrock_logging ? 1 : 0

  name = "role-${module.naming.id}-bedrock-logging"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
        }
        Action = "sts:AssumeRole"
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

  tags = merge(
    local.tags,
    {
      Name = "role-${module.naming.id}-bedrock-logging"
    }
  )
}

# IAM Policy for Bedrock Logging Role
resource "aws_iam_role_policy" "bedrock_logging" {
  count = var.enable_bedrock_logging ? 1 : 0

  name = "policy-${module.naming.id}-bedrock-logging"
  role = aws_iam_role.bedrock_logging[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.bedrock_logs[0].arn}:log-stream:aws/bedrock/modelinvocations"
      }
    ]
  })
}

# Bedrock Model Invocation Logging Configuration
# Logs model invocations to CloudWatch Logs
resource "aws_bedrock_model_invocation_logging_configuration" "main" {
  count = var.enable_bedrock_logging ? 1 : 0

  logging_config {
    cloudwatch_config {
      log_group_name = aws_cloudwatch_log_group.bedrock_logs[0].name
      role_arn       = aws_iam_role.bedrock_logging[0].arn
    }

    text_data_delivery_enabled = true
  }

  depends_on = [
    aws_cloudwatch_log_group.bedrock_logs,
    aws_iam_role.bedrock_logging
  ]
}

# Bedrock Foundation Model Access
# This data source lists available models - actual model access is granted via:
# - AWS Console: Amazon Bedrock > Model access
# - AWS CLI: aws bedrock put-foundation-model-entitlement
# - SCPs: Control at organization level (recommended for restricting models)
data "aws_bedrock_foundation_models" "available" {
  by_provider = "Amazon"
}

# Output available models for reference
output "bedrock_available_models" {
  description = "List of available Amazon Bedrock foundation models"
  value       = data.aws_bedrock_foundation_models.available.model_summaries[*].model_id
}

