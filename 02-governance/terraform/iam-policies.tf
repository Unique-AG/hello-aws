#######################################
# IAM Policies for Governance
#######################################
#
# Account-specific IAM policies for governance operations.
# These policies provide least-privilege access for
# governance-related tasks within this workload account.
#######################################

# Example: Budget viewer policy
# Uncomment and customize as needed
# resource "aws_iam_policy" "budget_viewer" {
#   name        = "${module.naming.iam_policy_prefix}-budget-viewer"
#   description = "Allows viewing budget information"
#
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Effect = "Allow"
#         Action = [
#           "budgets:ViewBudget",
#           "budgets:DescribeBudgets"
#         ]
#         Resource = "*"
#       }
#     ]
#   })
#
#   tags = module.naming.tags
# }

# Note: Add account-specific IAM policies here as needed.

