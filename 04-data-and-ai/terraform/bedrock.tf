# Bedrock model invocation logging to CloudWatch Logs
# Model access is controlled at the organization level via SCPs

resource "aws_cloudwatch_log_group" "bedrock_logs" {
  count = var.enable_bedrock_logging ? 1 : 0

  name              = "${module.naming.log_group_prefix}/bedrock/model-invocations"
  retention_in_days = max(var.cloudwatch_log_retention_days, 365)
  kms_key_id        = local.infrastructure.kms_key_cloudwatch_logs_arn

  tags = {
    Name    = "log-${module.naming.id}-bedrock"
    Purpose = "bedrock-model-invocation-logs"
  }
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
      values   = ["arn:aws:bedrock:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }
}

resource "aws_iam_role" "bedrock_logging" {
  count = var.enable_bedrock_logging ? 1 : 0

  name               = "role-${module.naming.id}-bedrock-logging"
  assume_role_policy = data.aws_iam_policy_document.bedrock_logging_assume[0].json

  tags = {
    Name = "role-${module.naming.id}-bedrock-logging"
  }
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

locals {
  # Bedrock's cross-region profile prefixes follow the region's geography; others fall back to global.
  bedrock_geo_prefix = coalesce(var.bedrock_geo_prefix, lookup({ us = "us", eu = "eu", ap = "apac" }, split("-", var.aws_region)[0], "global"))

  bedrock_profile_sources = {
    for k, v in var.bedrock_inference_profiles : k => (
      v.source_type == "inference-profile" ? "${coalesce(v.geo, local.bedrock_geo_prefix)}.${v.model_id}" : v.model_id
    )
  }
}

# Application Inference Profiles
# Wrap system cross-region inference profiles for per-model cost tracking and CloudWatch metrics
# LiteLLM and workloads can invoke these via the account-scoped ARN
resource "aws_bedrock_inference_profile" "model" {
  for_each = var.bedrock_inference_profiles

  name = "${module.naming.id}-${each.key}"

  model_source {
    copy_from = "arn:aws:bedrock:${var.aws_region}::${each.value.source_type}/${local.bedrock_profile_sources[each.key]}"
  }

  tags = {
    Name  = "${module.naming.id}-${each.key}"
    Model = local.bedrock_profile_sources[each.key]
  }
}

data "aws_bedrock_foundation_models" "available" {
  by_provider = "Amazon"
}
