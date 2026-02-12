# Minimum 365 days retention for compliance (except sandbox)
resource "aws_cloudwatch_log_group" "terraform" {
  name              = "${module.naming.log_group_prefix}/terraform"
  retention_in_days = var.environment == "sbx" ? var.cloudwatch_log_retention_days : max(var.cloudwatch_log_retention_days, 365)

  kms_key_id = var.enable_server_side_encryption ? aws_kms_key.terraform_state[0].arn : null

  depends_on = [
    aws_kms_key.terraform_state
  ]

  tags = merge(
    local.tags,
    {
      Name        = "${module.naming.log_group_prefix}/terraform"
      Description = "CloudWatch log group for Terraform operations"
    }
  )
}
