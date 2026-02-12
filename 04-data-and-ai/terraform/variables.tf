variable "aws_region" {
  description = "The AWS region where resources will be created"
  type        = string
  default     = "eu-central-2"
}

variable "aws_account_id" {
  description = "AWS account ID (for deterministic naming, recommended for CI/CD)"
  type        = string
  default     = null
}

variable "org" {
  description = "Organization identifier"
  type        = string
  default     = "unique"
}

variable "org_moniker" {
  description = "Organization moniker (short abbreviation)"
  type        = string
  default     = "uq"
}

variable "product" {
  description = "Product identifier (for display and tags)"
  type        = string
}

variable "product_moniker" {
  description = "Product moniker for resource names (shortened version of product)"
  type        = string
}

variable "environment" {
  description = "Environment name (prod, stag, dev, sbx)"
  type        = string
}

variable "semantic_version" {
  description = "Semantic version (e.g., 1.0.0). Set by CI/CD"
  type        = string
  default     = "0.0.0"
}

# Terraform State Configuration (for remote state access)
variable "terraform_state_bucket" {
  description = "S3 bucket name for Terraform state (from bootstrap layer). If not provided, computed from naming module."
  type        = string
  default     = null
}

variable "terraform_state_kms_key_id" {
  description = "KMS key ID/ARN for Terraform state encryption (from bootstrap layer). If not provided, computed from naming module."
  type        = string
  default     = null
}

# Managed Prometheus
variable "enable_managed_prometheus" {
  description = "Enable Amazon Managed Service for Prometheus"
  type        = bool
  default     = true
}

# Managed Grafana
variable "enable_managed_grafana" {
  description = "Enable Amazon Managed Grafana"
  type        = bool
  default     = true
}

# Bedrock
variable "enable_bedrock_logging" {
  description = "Enable Bedrock model invocation logging to CloudWatch Logs"
  type        = bool
  default     = true
}

variable "bedrock_inference_profiles" {
  description = "Application inference profiles for cost tracking and CloudWatch metrics. source_type is 'inference-profile' (cross-region) or 'foundation-model' (single-region)."
  type = map(object({
    model_id    = string
    source_type = optional(string, "inference-profile")
  }))
  default = {
    # EU cross-region inference profiles (Anthropic Claude via LiteLLM)
    "claude-sonnet-4-5" = { model_id = "eu.anthropic.claude-sonnet-4-5-20250929-v1:0" }
    "claude-opus-4-5"   = { model_id = "eu.anthropic.claude-opus-4-5-20251101-v1:0" }
    "claude-opus-4-6"   = { model_id = "eu.anthropic.claude-opus-4-6-v1" }
    "claude-haiku-4-5"  = { model_id = "eu.anthropic.claude-haiku-4-5-20251001-v1:0" }
    # Swiss-local foundation models (run natively in eu-central-2, no cross-region)
    "claude-3-5-sonnet"   = { model_id = "anthropic.claude-3-5-sonnet-20240620-v1:0", source_type = "foundation-model" }
    "claude-3-haiku"      = { model_id = "anthropic.claude-3-haiku-20240307-v1:0", source_type = "foundation-model" }
    "cohere-embed-v4"     = { model_id = "cohere.embed-v4:0", source_type = "foundation-model" }
    "titan-embed-text-v2" = { model_id = "amazon.titan-embed-text-v2:0", source_type = "foundation-model" }
  }
}

# CloudWatch
variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
}

# Aurora PostgreSQL
variable "aurora_engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "14.19"
}

variable "aurora_database_name" {
  description = "Name of the default database to create"
  type        = string
  default     = "appdb"
}

variable "postgresql_databases" {
  description = "Map of databases to create with connection string secrets"
  type = map(object({
    name = string
  }))
  default = {
    "app-repository"   = { name = "app_repository" }
    "chat"             = { name = "chat" }
    "ingestion"        = { name = "ingestion" }
    "litellm"          = { name = "litellm" }
    "scope-management" = { name = "scope_management" }
    "theme"            = { name = "theme" }
  }
}

variable "psql_host_secret_name" {
  description = "Secret name for PostgreSQL host"
  type        = string
  default     = "psql-host"
}

variable "psql_port_secret_name" {
  description = "Secret name for PostgreSQL port"
  type        = string
  default     = "psql-port"
}

variable "psql_username_secret_name" {
  description = "Secret name for PostgreSQL username"
  type        = string
  default     = "psql-username"
}

variable "psql_password_secret_name" {
  description = "Secret name for PostgreSQL password"
  type        = string
  default     = "psql-password"
}

variable "redis_host_secret_name" {
  description = "Secret name for Redis host"
  type        = string
  default     = "redis-host"
}

variable "redis_port_secret_name" {
  description = "Secret name for Redis port"
  type        = string
  default     = "redis-port"
}

variable "encryption_key_app_repository_secret_name" {
  description = "Secret name for application repository encryption key"
  type        = string
  default     = "encryption-key-app-repository"
}

variable "encryption_key_node_chat_lxm_secret_name" {
  description = "Secret name for node chat LXM encryption key"
  type        = string
  default     = "encryption-key-node-chat-lxm"
}

variable "encryption_key_ingestion_secret_name" {
  description = "Secret name for ingestion encryption key"
  type        = string
  default     = "encryption-key-ingestion"
}

variable "zitadel_db_user_password_secret_name" {
  description = "Secret name for Zitadel database user password"
  type        = string
  default     = "zitadel-db-user-password"
}

variable "zitadel_master_key_secret_name" {
  description = "Secret name for Zitadel master key"
  type        = string
  default     = "zitadel-master-key"
}

variable "zitadel_pat_secret_name" {
  description = "Secret name for Zitadel PAT"
  type        = string
  default     = "manual-zitadel-scope-mgmt-pat"
}

variable "rabbitmq_password_chat_secret_name" {
  description = "Secret name for RabbitMQ password for chat service"
  type        = string
  default     = "rabbitmq-password-chat"
}

variable "s3_application_data_bucket_secret_name" {
  description = "Secret name for S3 application data bucket name"
  type        = string
  default     = "s3-application-data-bucket"
}

variable "s3_application_data_bucket_arn_secret_name" {
  description = "Secret name for S3 application data bucket ARN"
  type        = string
  default     = "s3-application-data-bucket-arn"
}

variable "s3_ai_data_bucket_secret_name" {
  description = "Secret name for S3 AI data bucket name"
  type        = string
  default     = "s3-ai-data-bucket"
}

variable "s3_ai_data_bucket_arn_secret_name" {
  description = "Secret name for S3 AI data bucket ARN"
  type        = string
  default     = "s3-ai-data-bucket-arn"
}

variable "s3_access_key_id_secret_name" {
  description = "Secret name for S3 access key ID"
  type        = string
  default     = "s3-access-key-id"
}

variable "s3_secret_access_key_secret_name" {
  description = "Secret name for S3 secret access key"
  type        = string
  default     = "s3-secret-access-key"
}

variable "s3_endpoint_secret_name" {
  description = "Secret name for S3 endpoint URL"
  type        = string
  default     = "s3-endpoint"
}

variable "s3_region_secret_name" {
  description = "Secret name for S3 region"
  type        = string
  default     = "s3-region"
}

variable "azure_openai_endpoint_definitions_secret_name" {
  description = "Secret name for OpenAI endpoint definitions (points to LiteLLM proxy)"
  type        = string
  default     = "azure-openai-endpoint-definitions"
}

variable "litellm_proxy_master_key_secret_name" {
  description = "Secret name for LiteLLM proxy master key"
  type        = string
  default     = "litellm-proxy-master-key"
}

variable "litellm_salt_key_secret_name" {
  description = "Secret name for LiteLLM salt key"
  type        = string
  default     = "litellm-salt-key"
}

variable "rds_ca_bundle_secret_name" {
  description = "Secret name for RDS CA certificate bundle"
  type        = string
  default     = "rds-ca-bundle"
}

variable "aurora_instance_class" {
  description = "Instance class for Aurora cluster instances"
  type        = string
  default     = "db.r6g.large"
}

variable "aurora_instance_count" {
  description = "Number of Aurora instances in the cluster"
  type        = number
  default     = 2
}

variable "aurora_backup_retention_period" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7
}

variable "aurora_preferred_backup_window" {
  description = "Preferred backup window (UTC)"
  type        = string
  default     = "03:00-04:00"
}

variable "aurora_preferred_maintenance_window" {
  description = "Preferred maintenance window (UTC)"
  type        = string
  default     = "sun:04:00-sun:05:00"
}

variable "aurora_deletion_protection" {
  description = "Enable deletion protection for Aurora cluster"
  type        = bool
  default     = true
}

variable "aurora_skip_final_snapshot" {
  description = "Skip final snapshot when deleting cluster"
  type        = bool
  default     = false
}

variable "aurora_performance_insights_enabled" {
  description = "Enable Performance Insights for Aurora instances"
  type        = bool
  default     = true
}

# ElastiCache Redis
variable "elasticache_engine_version" {
  description = "ElastiCache Redis engine version"
  type        = string
  default     = "7.1"
}

variable "elasticache_node_type" {
  description = "ElastiCache node instance type"
  type        = string
  default     = "cache.r7g.large"
}

variable "elasticache_num_cache_nodes" {
  description = "Number of cache nodes in the replication group"
  type        = number
  default     = 2
}

variable "elasticache_parameter_family" {
  description = "ElastiCache parameter family"
  type        = string
  default     = "redis7"
}

variable "elasticache_automatic_failover_enabled" {
  description = "Enable automatic failover for ElastiCache"
  type        = bool
  default     = true
}

variable "elasticache_multi_az_enabled" {
  description = "Enable Multi-AZ for ElastiCache"
  type        = bool
  default     = true
}

variable "elasticache_snapshot_retention_limit" {
  description = "Number of days to retain ElastiCache snapshots"
  type        = number
  default     = 5
}

variable "elasticache_snapshot_window" {
  description = "Daily time range for ElastiCache snapshots (UTC)"
  type        = string
  default     = "03:00-05:00"
}

variable "elasticache_maintenance_window" {
  description = "Weekly maintenance window for ElastiCache (UTC)"
  type        = string
  default     = "sun:05:00-sun:06:00"
}

# Secrets Manager
variable "secrets_recovery_window_days" {
  description = "Number of days before permanently deleting secrets (0 for immediate deletion in dev/sbx)"
  type        = number
  default     = 30
}

# VPC Endpoints
variable "enable_aurora_endpoint" {
  description = "Enable Aurora (RDS API) Interface Endpoint"
  type        = bool
  default     = true
}

variable "enable_elasticache_endpoint" {
  description = "Enable ElastiCache Interface Endpoint"
  type        = bool
  default     = true
}
