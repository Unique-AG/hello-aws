#######################################
# AWS Config Rules
#######################################
#
# Account-specific Config rules for compliance monitoring.
# Note: AWS Config service itself should be enabled at the
# organization/landing zone level, not in workload accounts.
#
# These rules enforce account-specific compliance requirements.
#######################################

# Example: Required tags rule
# Uncomment and customize as needed
# resource "aws_config_config_rule" "required_tags" {
#   name = "required-tags-${module.naming.id}"
#
#   source {
#     owner             = "AWS"
#     source_identifier = "REQUIRED_TAGS"
#   }
#
#   input_parameters = jsonencode({
#     tag1Key = "org:Name"
#     tag2Key = "cost:CostCenter"
#     tag3Key = "automation:ManagedBy"
#     tag4Key = "client:Environment"
#   })
#
#   scope {
#     compliance_resource_types = [
#       "AWS::EC2::Instance",
#       "AWS::RDS::DBInstance",
#       "AWS::S3::Bucket",
#       "AWS::EKS::Cluster"
#     ]
#   }
#
#   tags = module.naming.tags
# }

# Note: Add account-specific Config rules here as needed.
# The Config service should be enabled at the organization level.

