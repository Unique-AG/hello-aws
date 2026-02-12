output "budget_name" {
  description = "Name of the AWS Budget"
  value       = aws_budgets_budget.monthly_budget.name
}

output "budget_arn" {
  description = "ARN of the AWS Budget"
  value       = aws_budgets_budget.monthly_budget.arn
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}
