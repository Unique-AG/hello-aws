# Managed Prometheus Workspace
# Access: IAM-gated (SigV4) + VPC endpoint in infrastructure layer
resource "aws_prometheus_workspace" "main" {
  count = var.enable_managed_prometheus ? 1 : 0

  alias = "prometheus-${module.naming.id}"

  logging_configuration {
    log_group_arn = "${data.aws_cloudwatch_log_group.infrastructure.arn}:*"
  }

  tags = {
    Name    = "prometheus-${module.naming.id}"
    Purpose = "metrics-collection"
  }
}

# Security Group for Grafana VPC configuration
resource "aws_security_group" "grafana" {
  count = var.enable_managed_grafana ? 1 : 0

  name        = "${module.naming.id}-grafana"
  description = "Security group for Managed Grafana workspace ENIs"
  vpc_id      = local.infrastructure.vpc_id

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "sg-${module.naming.id}-grafana"
  }
}

resource "aws_vpc_security_group_egress_rule" "grafana_to_vpc" {
  count = var.enable_managed_grafana ? 1 : 0

  security_group_id = aws_security_group.grafana[0].id
  description       = "HTTPS to VPC for data source access"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = data.aws_vpc.main.cidr_block
}

# Managed Grafana Workspace (VPC-only access)
resource "aws_grafana_workspace" "main" {
  count = var.enable_managed_grafana ? 1 : 0

  name                     = "grafana-${module.naming.id}"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["SAML"]
  permission_type          = "SERVICE_MANAGED"
  role_arn                 = aws_iam_role.grafana[0].arn
  data_sources             = ["PROMETHEUS", "CLOUDWATCH"]

  vpc_configuration {
    subnet_ids         = local.infrastructure.private_subnet_ids
    security_group_ids = [aws_security_group.grafana[0].id]
  }

  tags = {
    Name    = "grafana-${module.naming.id}"
    Purpose = "visualization"
  }

  depends_on = [
    aws_iam_role.grafana,
    aws_iam_role_policy.grafana_vpc,
  ]
}

# IAM Role for Managed Grafana

data "aws_iam_policy_document" "grafana_assume" {
  count = var.enable_managed_grafana ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["grafana.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "grafana" {
  count = var.enable_managed_grafana ? 1 : 0

  name               = "role-${module.naming.id}-grafana"
  assume_role_policy = data.aws_iam_policy_document.grafana_assume[0].json

  tags = {
    Name = "role-${module.naming.id}-grafana"
  }
}

# Grafana → VPC ENI management (required for vpc_configuration)

data "aws_iam_policy_document" "grafana_vpc" {
  count = var.enable_managed_grafana ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeNetworkInterfaces",
      "ec2:CreateNetworkInterface",
      "ec2:CreateNetworkInterfacePermission",
      "ec2:DeleteNetworkInterface",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [data.aws_region.current.name]
    }
  }
}

resource "aws_iam_role_policy" "grafana_vpc" {
  count = var.enable_managed_grafana ? 1 : 0

  name   = "policy-${module.naming.id}-grafana-vpc"
  role   = aws_iam_role.grafana[0].id
  policy = data.aws_iam_policy_document.grafana_vpc[0].json
}

# Grafana → Prometheus access

data "aws_iam_policy_document" "grafana_prometheus" {
  count = var.enable_managed_grafana && var.enable_managed_prometheus ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "aps:ListWorkspaces",
      "aps:DescribeWorkspace",
      "aps:QueryMetrics",
      "aps:GetMetricMetadata",
      "aps:GetLabels",
      "aps:GetSeries",
    ]
    resources = [aws_prometheus_workspace.main[0].arn]
  }
}

resource "aws_iam_role_policy" "grafana_prometheus" {
  count = var.enable_managed_grafana && var.enable_managed_prometheus ? 1 : 0

  name   = "policy-${module.naming.id}-grafana-prometheus"
  role   = aws_iam_role.grafana[0].id
  policy = data.aws_iam_policy_document.grafana_prometheus[0].json
}

# Grafana → CloudWatch access (scoped to this account)

data "aws_iam_policy_document" "grafana_cloudwatch" {
  count = var.enable_managed_grafana ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "cloudwatch:DescribeAlarmsForMetric",
      "cloudwatch:DescribeAlarmHistory",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:ListMetrics",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:GetMetricData",
      "cloudwatch:GetInsightRuleReport",
    ]
    resources = ["arn:aws:cloudwatch:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:DescribeLogGroups",
      "logs:GetLogGroupFields",
      "logs:StartQuery",
      "logs:StopQuery",
      "logs:GetQueryResults",
      "logs:GetLogEvents",
    ]
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"]
  }
}

resource "aws_iam_role_policy" "grafana_cloudwatch" {
  count = var.enable_managed_grafana ? 1 : 0

  name   = "policy-${module.naming.id}-grafana-cloudwatch"
  role   = aws_iam_role.grafana[0].id
  policy = data.aws_iam_policy_document.grafana_cloudwatch[0].json
}
