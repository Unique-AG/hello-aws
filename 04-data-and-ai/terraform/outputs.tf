# Managed Prometheus
output "prometheus_workspace_id" {
  description = "ID of the Managed Prometheus workspace"
  value       = var.enable_managed_prometheus ? aws_prometheus_workspace.main[0].id : null
}

output "prometheus_workspace_arn" {
  description = "ARN of the Managed Prometheus workspace"
  value       = var.enable_managed_prometheus ? aws_prometheus_workspace.main[0].arn : null
}

output "prometheus_workspace_endpoint" {
  description = "Prometheus query endpoint URL"
  value       = var.enable_managed_prometheus ? aws_prometheus_workspace.main[0].prometheus_endpoint : null
}

# Managed Grafana
output "grafana_workspace_id" {
  description = "ID of the Managed Grafana workspace"
  value       = var.enable_managed_grafana ? aws_grafana_workspace.main[0].id : null
}

output "grafana_workspace_endpoint" {
  description = "Grafana workspace endpoint URL"
  value       = var.enable_managed_grafana ? aws_grafana_workspace.main[0].endpoint : null
}

output "grafana_iam_role_arn" {
  description = "ARN of the IAM role for Managed Grafana"
  value       = var.enable_managed_grafana ? aws_iam_role.grafana[0].arn : null
}

# S3 Buckets
output "s3_bucket_application_data_id" {
  description = "ID of the application data S3 bucket"
  value       = aws_s3_bucket.application_data.id
}

output "s3_bucket_application_data_arn" {
  description = "ARN of the application data S3 bucket"
  value       = aws_s3_bucket.application_data.arn
}

output "s3_bucket_ai_data_id" {
  description = "ID of the AI data S3 bucket"
  value       = aws_s3_bucket.ai_data.id
}

output "s3_bucket_ai_data_arn" {
  description = "ARN of the AI data S3 bucket"
  value       = aws_s3_bucket.ai_data.arn
}

# Aurora PostgreSQL
output "aurora_cluster_id" {
  description = "ID of the Aurora PostgreSQL cluster"
  value       = aws_rds_cluster.postgres.cluster_identifier
}

output "aurora_cluster_arn" {
  description = "ARN of the Aurora PostgreSQL cluster"
  value       = aws_rds_cluster.postgres.arn
}

output "aurora_cluster_endpoint" {
  description = "Writer endpoint for the Aurora PostgreSQL cluster"
  value       = aws_rds_cluster.postgres.endpoint
}

output "aurora_cluster_reader_endpoint" {
  description = "Reader endpoint for the Aurora PostgreSQL cluster"
  value       = aws_rds_cluster.postgres.reader_endpoint
}

output "aurora_cluster_database_name" {
  description = "Name of the default database"
  value       = aws_rds_cluster.postgres.database_name
}

output "aurora_master_user_secret_arn" {
  description = "ARN of the AWS-managed secret containing the Aurora master user password"
  value       = try(aws_rds_cluster.postgres.master_user_secret[0].secret_arn, null)
}

# ElastiCache Redis
output "elasticache_replication_group_id" {
  description = "ID of the ElastiCache replication group"
  value       = aws_elasticache_replication_group.redis.replication_group_id
}

output "elasticache_configuration_endpoint_address" {
  description = "Configuration endpoint address for ElastiCache Redis"
  value       = aws_elasticache_replication_group.redis.configuration_endpoint_address
}

output "elasticache_primary_endpoint_address" {
  description = "Primary endpoint address for ElastiCache Redis"
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "elasticache_port" {
  description = "Port for ElastiCache Redis"
  value       = aws_elasticache_replication_group.redis.port
}

# IAM
output "s3_access_iam_user_name" {
  description = "IAM user name for S3 access key creation"
  value       = aws_iam_user.s3_access.name
}

# Region (for seed script)
output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

# PostgreSQL databases (for connection string construction in seed script)
output "postgresql_databases" {
  description = "Map of database keys to database names"
  value       = var.postgresql_databases
}

# Secrets Manager — consolidated ARN map (used by seed script and IAM policies)
output "secret_arns" {
  description = "Map of all Secrets Manager secret ARNs"
  value = {
    psql_host                         = aws_secretsmanager_secret.psql_host.arn
    psql_port                         = aws_secretsmanager_secret.psql_port.arn
    psql_username                     = aws_secretsmanager_secret.psql_username.arn
    psql_password                     = aws_secretsmanager_secret.psql_password.arn
    redis_host                        = aws_secretsmanager_secret.redis_host.arn
    redis_port                        = aws_secretsmanager_secret.redis_port.arn
    encryption_key_app_repository     = aws_secretsmanager_secret.encryption_key_app_repository.arn
    encryption_key_node_chat_lxm      = aws_secretsmanager_secret.encryption_key_node_chat_lxm.arn
    encryption_key_ingestion          = aws_secretsmanager_secret.encryption_key_ingestion.arn
    zitadel_db_user_password          = aws_secretsmanager_secret.zitadel_db_user_password.arn
    zitadel_master_key                = aws_secretsmanager_secret.zitadel_master_key.arn
    zitadel_pat                       = aws_secretsmanager_secret.zitadel_pat.arn
    rabbitmq_password_chat            = aws_secretsmanager_secret.rabbitmq_password_chat.arn
    litellm_proxy_master_key          = aws_secretsmanager_secret.litellm_proxy_master_key.arn
    litellm_salt_key                  = aws_secretsmanager_secret.litellm_salt_key.arn
    azure_openai_endpoint_definitions = aws_secretsmanager_secret.azure_openai_endpoint_definitions.arn
    s3_application_data_bucket        = aws_secretsmanager_secret.s3_application_data_bucket.arn
    s3_ai_data_bucket                 = aws_secretsmanager_secret.s3_ai_data_bucket.arn
    s3_application_data_bucket_arn    = aws_secretsmanager_secret.s3_application_data_bucket_arn.arn
    s3_ai_data_bucket_arn             = aws_secretsmanager_secret.s3_ai_data_bucket_arn.arn
    s3_access_key_id                  = aws_secretsmanager_secret.s3_access_key_id.arn
    s3_secret_access_key              = aws_secretsmanager_secret.s3_secret_access_key.arn
    s3_endpoint                       = aws_secretsmanager_secret.s3_endpoint.arn
    s3_region                         = aws_secretsmanager_secret.s3_region.arn
    rds_ca_bundle                     = aws_secretsmanager_secret.rds_ca_bundle.arn
  }
}

# PostgreSQL connection string secret ARNs (dynamic, from for_each)
output "psql_connection_string_secret_arns" {
  description = "Map of database keys to their connection string secret ARNs"
  value       = { for k, v in aws_secretsmanager_secret.psql_connection_string : k => v.arn }
}

# VPC Endpoints
output "aurora_endpoint_id" {
  description = "ID of the Aurora (RDS API) Interface Endpoint"
  value       = var.enable_aurora_endpoint ? aws_vpc_endpoint.aurora[0].id : null
}

output "elasticache_endpoint_id" {
  description = "ID of the ElastiCache Interface Endpoint"
  value       = var.enable_elasticache_endpoint ? aws_vpc_endpoint.elasticache[0].id : null
}

# Bedrock
output "bedrock_available_models" {
  description = "List of available Amazon Bedrock foundation models"
  value       = data.aws_bedrock_foundation_models.available.model_summaries[*].model_id
}

output "bedrock_inference_profile_arns" {
  description = "Map of application inference profile names to their ARNs"
  value       = { for k, v in aws_bedrock_inference_profile.model : k => v.arn }
}
