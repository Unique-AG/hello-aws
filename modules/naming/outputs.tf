#######################################
# Core Outputs
#######################################

output "id" {
  description = "Full resource ID (e.g., df-unique-sbx-euc2)"
  value       = local.id
}

output "id_short" {
  description = "Short resource ID (e.g., df-unique-x-euc2)"
  value       = local.id_short
}

#######################################
# Resource-Specific Names
#######################################

output "s3_bucket_prefix" {
  description = "S3 bucket name prefix (max 63 chars)"
  value       = local.s3_bucket_prefix
}

output "s3_bucket_full" {
  description = "S3 bucket name with account ID for uniqueness (format: s3-{id_short}-{account_id})"
  value       = "${local.s3_bucket_prefix}-${local.account_id}"
}

output "dynamodb_table_prefix" {
  description = "DynamoDB table name prefix (format: dynamodb-{id})"
  value       = local.dynamodb_table_prefix
}

output "kms_alias_prefix" {
  description = "KMS alias prefix without 'alias/' (format: kms-{id})"
  value       = local.kms_alias_prefix
}

output "iam_policy_prefix" {
  description = "IAM policy name prefix (max 100 chars, format: iam-{id})"
  value       = local.iam_policy_prefix
}

output "eks_cluster_name" {
  description = "EKS cluster name (max 100 chars, format: eks-{id})"
  value       = local.eks_cluster_name
}

output "rds_identifier" {
  description = "RDS instance identifier (max 63 chars, format: rds-{id})"
  value       = local.rds_identifier
}

output "elasticache_cluster_id" {
  description = "ElastiCache cluster ID (max 50 chars, format: elasticache-{id_short})"
  value       = local.elasticache_cluster_id
}

output "lb_name" {
  description = "ALB/NLB name (max 32 chars, format: alb-{id_short})"
  value       = local.lb_name
}

output "tg_name_prefix" {
  description = "Target group name prefix (max 28 chars, format: tg-{id_short})"
  value       = local.tg_name_prefix
}

output "iam_role_prefix" {
  description = "IAM role name prefix (max 50 chars, format: iam-{id})"
  value       = local.iam_role_prefix
}

output "lambda_prefix" {
  description = "Lambda function name prefix (max 50 chars, format: lambda-{id})"
  value       = local.lambda_prefix
}

output "sg_name_prefix" {
  description = "Security group name prefix (format: sg-{id})"
  value       = local.sg_name_prefix
}

output "log_group_prefix" {
  description = "CloudWatch log group prefix"
  value       = local.log_group_prefix
}

#######################################
# Context
#######################################

output "account_id" {
  description = "AWS Account ID"
  value       = local.account_id
}

output "region" {
  description = "AWS Region"
  value       = local.region
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "environment_short" {
  description = "Environment short code"
  value       = local.env_short[var.environment]
}

#######################################
# Tags
#######################################

output "tags" {
  description = "Standard resource tags"
  value       = local.tags
}

output "tags_as_list" {
  description = "Tags as list of key-value objects (for ASG)"
  value = [
    for key, value in local.tags : {
      key                 = key
      value               = value
      propagate_at_launch = true
    }
  ]
}

