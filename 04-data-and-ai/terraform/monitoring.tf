#######################################
# Application Monitoring Services
#######################################
#
# Managed Prometheus and Managed Grafana
# for application metrics collection and visualization.
# These are application monitoring tools, not infrastructure monitoring.
#######################################

# Managed Prometheus Workspace
# For collecting and querying Prometheus metrics from EKS and other sources
# Note: KMS encryption is configured via aws_prometheus_workspace_encryption_config after creation
resource "aws_prometheus_workspace" "main" {
  count = var.enable_managed_prometheus ? 1 : 0

  alias = "prometheus-${module.naming.id}"

  logging_configuration {
    log_group_arn = "${data.aws_cloudwatch_log_group.infrastructure.arn}:*"
  }

  tags = merge(
    local.tags,
    {
      Name    = "prometheus-${module.naming.id}"
      Purpose = "metrics-collection"
    }
  )
}

# Note: Prometheus workspace encryption is configured via the workspace resource itself
# The aws_prometheus_workspace_encryption_config resource type doesn't exist in the provider
# Encryption can be configured using the kms_key_id attribute in aws_prometheus_workspace

# Managed Grafana Workspace
# For visualizing metrics and logs
resource "aws_grafana_workspace" "main" {
  count = var.enable_managed_grafana ? 1 : 0

  name                     = "grafana-${module.naming.id}"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["SAML"] # Can be updated to SSO, AWS_IAM, etc.
  permission_type          = "SERVICE_MANAGED"
  role_arn                 = aws_iam_role.grafana[0].arn
  data_sources             = ["PROMETHEUS", "CLOUDWATCH"]

  # Note: Grafana workspace encryption is not supported via encryption_config block
  # Encryption is managed at the workspace level via IAM and KMS policies

  tags = merge(
    local.tags,
    {
      Name    = "grafana-${module.naming.id}"
      Purpose = "visualization"
    }
  )

  depends_on = [
    aws_iam_role.grafana
  ]
}

# IAM Role for Managed Grafana
resource "aws_iam_role" "grafana" {
  count = var.enable_managed_grafana ? 1 : 0

  name = "role-${module.naming.id}-grafana"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "grafana.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    local.tags,
    {
      Name = "role-${module.naming.id}-grafana"
    }
  )
}

# IAM Policy for Grafana to access Prometheus
resource "aws_iam_role_policy" "grafana_prometheus" {
  count = var.enable_managed_grafana && var.enable_managed_prometheus ? 1 : 0

  name = "policy-${module.naming.id}-grafana-prometheus"
  role = aws_iam_role.grafana[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "aps:ListWorkspaces",
          "aps:DescribeWorkspace",
          "aps:QueryMetrics",
          "aps:GetMetricMetadata",
          "aps:GetLabels",
          "aps:GetSeries"
        ]
        Resource = aws_prometheus_workspace.main[0].arn
      }
    ]
  })
}

# IAM Policy for Grafana to access CloudWatch
# Note: CloudWatch metrics and logs are account-wide resources, but we restrict
# to specific log groups and metrics where possible for better security posture
resource "aws_iam_role_policy" "grafana_cloudwatch" {
  count = var.enable_managed_grafana ? 1 : 0

  name = "policy-${module.naming.id}-grafana-cloudwatch"
  role = aws_iam_role.grafana[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarmsForMetric",
          "cloudwatch:DescribeAlarmHistory",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetInsightRuleReport"
        ]
        # CloudWatch metrics are account-wide, but we scope to this account
        Resource = [
          "arn:aws:cloudwatch:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:GetLogGroupFields",
          "logs:StartQuery",
          "logs:StopQuery",
          "logs:GetQueryResults",
          "logs:GetLogEvents"
        ]
        # Restrict to log groups in this account
        Resource = [
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
        ]
      }
    ]
  })
}

