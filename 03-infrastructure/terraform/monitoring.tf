resource "aws_cloudwatch_log_group" "infrastructure" {
  name              = "${module.naming.log_group_prefix}/infrastructure"
  retention_in_days = var.environment == "sbx" ? var.cloudwatch_log_retention_days : max(var.cloudwatch_log_retention_days, 365)
  kms_key_id        = aws_kms_key.cloudwatch_logs.arn

  tags = {
    Name    = "log-${module.naming.id}-infrastructure"
    Purpose = "infrastructure-logs"
  }
}

# SNS Topic for Infrastructure Alerts
resource "aws_sns_topic" "alerts" {
  name              = "${module.naming.id}-infrastructure-alerts"
  kms_master_key_id = aws_kms_key.general.arn

  tags = {
    Name    = "${module.naming.id}-infrastructure-alerts"
    Purpose = "infrastructure-alerts"
  }
}

resource "aws_sns_topic_subscription" "alert_email" {
  count = length(var.alert_email_endpoints)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email_endpoints[count.index]
}

# NAT Gateway ErrorPortAllocation Alarm
resource "aws_cloudwatch_metric_alarm" "nat_error_port_allocation" {
  count = var.enable_nat_gateway ? local.nat_gateway_count : 0

  alarm_name          = "${module.naming.id}-nat-${count.index + 1}-error-port-allocation"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ErrorPortAllocation"
  namespace           = "AWS/NATGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "NAT Gateway ${count.index + 1} port allocation errors detected"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    NatGatewayId = aws_nat_gateway.main[count.index].id
  }
}

# NAT Gateway PacketsDropCount Alarm
resource "aws_cloudwatch_metric_alarm" "nat_packets_drop" {
  count = var.enable_nat_gateway ? local.nat_gateway_count : 0

  alarm_name          = "${module.naming.id}-nat-${count.index + 1}-packets-drop"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "PacketsDropCount"
  namespace           = "AWS/NATGateway"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "NAT Gateway ${count.index + 1} is dropping packets"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    NatGatewayId = aws_nat_gateway.main[count.index].id
  }
}
