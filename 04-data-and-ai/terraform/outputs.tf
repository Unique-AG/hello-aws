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

# Secrets Manager — Secret Names
output "psql_host_secret_name" {
  description = "Secret name for PostgreSQL host"
  value       = aws_secretsmanager_secret.psql_host.name
}

output "psql_port_secret_name" {
  description = "Secret name for PostgreSQL port"
  value       = aws_secretsmanager_secret.psql_port.name
}

output "psql_username_secret_name" {
  description = "Secret name for PostgreSQL username"
  value       = aws_secretsmanager_secret.psql_username.name
}

output "psql_password_secret_name" {
  description = "Secret name for PostgreSQL password"
  value       = aws_secretsmanager_secret.psql_password.name
}

output "redis_host_secret_name" {
  description = "Secret name for Redis host"
  value       = aws_secretsmanager_secret.redis_host.name
}

output "redis_port_secret_name" {
  description = "Secret name for Redis port"
  value       = aws_secretsmanager_secret.redis_port.name
}

output "encryption_key_app_repository_secret_name" {
  description = "Secret name for application repository encryption key"
  value       = aws_secretsmanager_secret.encryption_key_app_repository.name
}

output "encryption_key_node_chat_lxm_secret_name" {
  description = "Secret name for node chat LXM encryption key"
  value       = aws_secretsmanager_secret.encryption_key_node_chat_lxm.name
}

output "encryption_key_ingestion_secret_name" {
  description = "Secret name for ingestion encryption key"
  value       = aws_secretsmanager_secret.encryption_key_ingestion.name
}

output "zitadel_db_user_password_secret_name" {
  description = "Secret name for Zitadel database user password"
  value       = aws_secretsmanager_secret.zitadel_db_user_password.name
}

output "zitadel_master_key_secret_name" {
  description = "Secret name for Zitadel master key"
  value       = aws_secretsmanager_secret.zitadel_master_key.name
}

output "zitadel_pat_secret_name" {
  description = "Secret name for Zitadel PAT"
  value       = aws_secretsmanager_secret.zitadel_pat.name
}

output "rabbitmq_password_chat_secret_name" {
  description = "Secret name for RabbitMQ password for chat"
  value       = aws_secretsmanager_secret.rabbitmq_password_chat.name
}

# Secrets Manager — ARNs (for IAM policies)
output "psql_host_secret_arn" {
  description = "ARN of the PostgreSQL host secret"
  value       = aws_secretsmanager_secret.psql_host.arn
}

output "psql_password_secret_arn" {
  description = "ARN of the PostgreSQL password secret"
  value       = aws_secretsmanager_secret.psql_password.arn
}

output "redis_host_secret_arn" {
  description = "ARN of the Redis host secret"
  value       = aws_secretsmanager_secret.redis_host.arn
}

# PostgreSQL Database Connection Strings
output "psql_database_connection_strings_secret_names" {
  description = "Map of database names to their connection string secret names"
  value       = { for k, v in aws_secretsmanager_secret.psql_connection_string : k => v.name }
}

# S3 Bucket Secrets
output "s3_application_data_bucket_secret_name" {
  description = "Secret name for S3 application data bucket"
  value       = aws_secretsmanager_secret.s3_application_data_bucket.name
}

output "s3_ai_data_bucket_secret_name" {
  description = "Secret name for S3 AI data bucket"
  value       = aws_secretsmanager_secret.s3_ai_data_bucket.name
}

output "s3_application_data_bucket_arn_secret_name" {
  description = "Secret name for S3 application data bucket ARN"
  value       = aws_secretsmanager_secret.s3_application_data_bucket_arn.name
}

output "s3_ai_data_bucket_arn_secret_name" {
  description = "Secret name for S3 AI data bucket ARN"
  value       = aws_secretsmanager_secret.s3_ai_data_bucket_arn.name
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
