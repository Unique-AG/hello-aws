# Bedrock model invocation logging to CloudWatch Logs
# Model access is controlled at the organization level via SCPs

resource "aws_cloudwatch_log_group" "bedrock_logs" {
  count = var.enable_bedrock_logging ? 1 : 0

  name              = "${module.naming.log_group_prefix}/bedrock/model-invocations"
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

data "aws_iam_policy_document" "bedrock_logging_assume" {
  count = var.enable_bedrock_logging ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }
}

resource "aws_iam_role" "bedrock_logging" {
  count = var.enable_bedrock_logging ? 1 : 0

  name               = "role-${module.naming.id}-bedrock-logging"
  assume_role_policy = data.aws_iam_policy_document.bedrock_logging_assume[0].json

  tags = merge(
    local.tags,
    {
      Name = "role-${module.naming.id}-bedrock-logging"
    }
  )
}

data "aws_iam_policy_document" "bedrock_logging" {
  count = var.enable_bedrock_logging ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.bedrock_logs[0].arn}:log-stream:*"]
  }
}

resource "aws_iam_role_policy" "bedrock_logging" {
  count = var.enable_bedrock_logging ? 1 : 0

  name   = "policy-${module.naming.id}-bedrock-logging"
  role   = aws_iam_role.bedrock_logging[0].id
  policy = data.aws_iam_policy_document.bedrock_logging[0].json
}

# Bedrock Model Invocation Logging Configuration
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

data "aws_bedrock_foundation_models" "available" {
  by_provider = "Amazon"
}
