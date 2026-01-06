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

# Naming module variables
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

variable "client" {
  description = "Client identifier"
  type        = string
  default     = "acme"
}

variable "client_name" {
  description = "Client full name (for display/tagging purposes)"
  type        = string
  default     = "Unique Dog Food AG"
}

variable "environment" {
  description = "Environment name (prod, stag, dev, sbx)"
  type        = string
}

# Governance tracking variables
variable "semantic_version" {
  description = "Semantic version (e.g., 1.0.0). Set by CI/CD"
  type        = string
  default     = "0.0.0"
}

# Terraform State Configuration (for remote state access)
# These are optional - if not provided, will be computed from naming module (same as bootstrap layer)
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

# Managed Prometheus Configuration
variable "enable_managed_prometheus" {
  description = "Enable Amazon Managed Service for Prometheus"
  type        = bool
  default     = true
}

# Managed Grafana Configuration
variable "enable_managed_grafana" {
  description = "Enable Amazon Managed Grafana"
  type        = bool
  default     = true
}

# Bedrock Configuration
variable "enable_bedrock_logging" {
  description = "Enable Bedrock model invocation logging to CloudWatch Logs"
  type        = bool
  default     = true
}

# CloudWatch Configuration
variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs (default: 30 days for production, override with 7 for fast teardown in dev/sbx)"
  type        = number
  default     = 30 # Production default - override in dev/sbx for fast teardown
}

# Aurora PostgreSQL Configuration
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

# PostgreSQL Databases (matching hello-azure-v2 pattern)
variable "postgresql_databases" {
  description = "Map of databases to create with connection string secrets"
  type = map(object({
    name = string
  }))
  default = {
    "app-repository"   = { name = "app_repository" }
    "chat"             = { name = "chat" }
    "ingestion"        = { name = "ingestion" }
    "scope-management" = { name = "scope_management" }
    "theme"            = { name = "theme" }
  }
}

# Secret names matching Azure Key Vault pattern for external-secrets compatibility
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
  description = "Secret name for Zitadel PAT (Personal Access Token)"
  type        = string
  default     = "manual-zitadel-scope-mgmt-pat"
}

variable "rabbitmq_password_chat_secret_name" {
  description = "Secret name for RabbitMQ password for chat service"
  type        = string
  default     = "rabbitmq-password-chat"
}

# S3 bucket secret names
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

# ElastiCache Redis Configuration
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

# Secrets Manager Configuration
variable "secrets_recovery_window_days" {
  description = "Number of days to wait before permanently deleting secrets (default: 30 days, 0 for immediate deletion in dev/sbx)"
  type        = number
  default     = 30 # Production default - override with 0 in dev/sbx for immediate deletion
}

# VPC Endpoints Configuration
variable "enable_rds_endpoint" {
  description = "Enable RDS Interface Endpoint (required for RDS API operations from pods)"
  type        = bool
  default     = true
}

variable "enable_elasticache_endpoint" {
  description = "Enable ElastiCache Interface Endpoint (required for ElastiCache API operations from pods)"
  type        = bool
  default     = true
}

