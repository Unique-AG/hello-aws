# CloudWatch log group for Terraform operations
# Uses hierarchical naming: /{org_moniker}/{client}/{environment}/terraform
# Example: /uq/acme/prod/terraform
# Retention: 365 days for compliance (except sandbox which uses shorter retention)
resource "aws_cloudwatch_log_group" "terraform" {
  name = "${module.naming.log_group_prefix}/terraform"
  # Minimum 365 days for compliance, except sandbox environment
  retention_in_days = var.environment == "sbx" ? var.cloudwatch_log_retention_days : max(var.cloudwatch_log_retention_days, 365)

  kms_key_id = var.enable_server_side_encryption ? aws_kms_key.terraform_state[0].arn : null

  # Ensure KMS key policy is updated before creating log group
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

