#######################################
# Native AWS Infrastructure Monitoring
#######################################
#
# CloudWatch Log Groups for infrastructure-level monitoring
# (VPC Flow Logs, etc.)
#
# Note: Application monitoring (Managed Prometheus) is in the 04-data-and-ai layer.
#######################################

# CloudWatch Log Group for Infrastructure
# Used for infrastructure-level logs (VPC Flow Logs, etc.)
# Retention: 365 days for compliance (except sandbox which uses shorter retention)
resource "aws_cloudwatch_log_group" "infrastructure" {
  name = "/${var.org_moniker}/${var.client}/${var.environment}/infrastructure"
  # Minimum 365 days for compliance, except sandbox environment
  retention_in_days = var.environment == "sbx" ? var.cloudwatch_log_retention_days : max(var.cloudwatch_log_retention_days, 365)
  kms_key_id        = aws_kms_key.cloudwatch_logs.arn

  tags = merge(
    local.tags,
    {
      Name    = "log-${module.naming.id}-infrastructure"
      Purpose = "infrastructure-logs"
    }
  )
}

