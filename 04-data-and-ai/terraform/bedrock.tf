#######################################
# Amazon Bedrock
#######################################
#
# Amazon Bedrock foundation model access with:
# - Private access via VPC endpoint
# - Model access configuration
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

# Bedrock Model Access Configuration
# Grants access to foundation models
resource "aws_bedrock_model_invocation_logging_configuration" "main" {
  count = var.enable_bedrock_logging ? 1 : 0

  logging_config {
    s3_config {
      bucket_name = aws_s3_bucket.ai_data.bucket
      key_prefix  = "bedrock-logs"
    }

    text_data_delivery_enabled = true
  }
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

