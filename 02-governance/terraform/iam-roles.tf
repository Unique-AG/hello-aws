#######################################
# IAM Roles for Governance
#######################################
#
# Account-specific IAM roles for governance operations.
# Provides least-privilege access for governance tasks
# within this workload account.
#######################################

# Example: Budget administrator role
# Uncomment and customize as needed
# resource "aws_iam_role" "budget_administrator" {
#   name = "${module.naming.iam_role_prefix}-budget-admin"
#
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Principal = {
#           AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
#         }
#         Action = "sts:AssumeRole"
#         Condition = {
#           StringEquals = {
#             "aws:RequestedRegion" = var.aws_region
#           }
#         }
#       }
#     ]
#   })
#
#   tags = module.naming.tags
# }
#
# resource "aws_iam_role_policy_attachment" "budget_administrator" {
#   role       = aws_iam_role.budget_administrator.name
#   policy_arn = aws_iam_policy.budget_viewer.arn
# }

# Note: Add account-specific IAM roles here as needed.
# For example:
# - Security auditor role
# - Compliance reviewer role
# - Budget administrator role

