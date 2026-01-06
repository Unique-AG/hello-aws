output "s3_bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.arn
}

output "kms_key_id" {
  description = "ID of the KMS key for state encryption"
  value       = var.enable_server_side_encryption ? aws_kms_key.terraform_state[0].id : null
}

output "kms_key_arn" {
  description = "ARN of the KMS key for state encryption"
  value       = var.enable_server_side_encryption ? aws_kms_key.terraform_state[0].arn : null
}

output "kms_key_alias" {
  description = "Alias of the KMS key for state encryption"
  value       = var.enable_server_side_encryption ? aws_kms_alias.terraform_state[0].name : null
}

output "github_actions_role_arn" {
  description = "ARN of the IAM role for GitHub Actions OIDC"
  value       = var.use_oidc && var.github_repository != "" ? aws_iam_role.github_actions[0].arn : null
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.terraform.name
}

output "aws_account_id" {
  description = "Current AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "Current AWS region"
  value       = data.aws_region.current.name
}

