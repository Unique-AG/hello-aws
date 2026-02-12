# Generated Credentials

# PostgreSQL Master Password
resource "random_password" "postgres_password" {
  keepers = {
    version = "1"
  }
  length  = 32
  special = false
  numeric = true
}

# PostgreSQL Secrets

resource "aws_secretsmanager_secret" "psql_host" {
  name                    = var.psql_host_secret_name
  description             = "PostgreSQL host endpoint"
  recovery_window_in_days = var.secrets_recovery_window_days
  kms_key_id              = local.infrastructure.kms_key_secrets_manager_arn

  tags = merge(local.tags, { Name = var.psql_host_secret_name, Purpose = "database-credentials" })
}

resource "aws_secretsmanager_secret_version" "psql_host" {
  secret_id     = aws_secretsmanager_secret.psql_host.id
  secret_string = aws_rds_cluster.postgres.endpoint
}

resource "aws_secretsmanager_secret" "psql_port" {
  name                    = var.psql_port_secret_name
  description             = "PostgreSQL port"
  recovery_window_in_days = var.secrets_recovery_window_days
  kms_key_id              = local.infrastructure.kms_key_secrets_manager_arn

  tags = merge(local.tags, { Name = var.psql_port_secret_name, Purpose = "database-credentials" })
}

resource "aws_secretsmanager_secret_version" "psql_port" {
  secret_id     = aws_secretsmanager_secret.psql_port.id
  secret_string = "5432"
}

resource "aws_secretsmanager_secret" "psql_username" {
  name                    = var.psql_username_secret_name
  description             = "PostgreSQL master username"
  recovery_window_in_days = var.secrets_recovery_window_days
  kms_key_id              = local.infrastructure.kms_key_secrets_manager_arn

  tags = merge(local.tags, { Name = var.psql_username_secret_name, Purpose = "database-credentials" })
}

resource "aws_secretsmanager_secret_version" "psql_username" {
  secret_id     = aws_secretsmanager_secret.psql_username.id
  secret_string = "dbadmin"
}

resource "aws_secretsmanager_secret" "psql_password" {
  name                    = var.psql_password_secret_name
  description             = "PostgreSQL master password"
  recovery_window_in_days = var.secrets_recovery_window_days
  kms_key_id              = local.infrastructure.kms_key_secrets_manager_arn

  tags = merge(local.tags, { Name = var.psql_password_secret_name, Purpose = "database-credentials" })
}

resource "aws_secretsmanager_secret_version" "psql_password" {
  secret_id     = aws_secretsmanager_secret.psql_password.id
  secret_string = random_password.postgres_password.result
}

# Redis Secrets

resource "aws_secretsmanager_secret" "redis_host" {
  name                    = var.redis_host_secret_name
  description             = "Redis cluster endpoint"
  recovery_window_in_days = var.secrets_recovery_window_days
  kms_key_id              = local.infrastructure.kms_key_secrets_manager_arn

  tags = merge(local.tags, { Name = var.redis_host_secret_name, Purpose = "redis-credentials" })
}

resource "aws_secretsmanager_secret_version" "redis_host" {
  secret_id = aws_secretsmanager_secret.redis_host.id
  secret_string = coalesce(
    aws_elasticache_replication_group.redis.configuration_endpoint_address,
    aws_elasticache_replication_group.redis.primary_endpoint_address
  )
}

resource "aws_secretsmanager_secret" "redis_port" {
  name                    = var.redis_port_secret_name
  description             = "Redis port"
  recovery_window_in_days = var.secrets_recovery_window_days
  kms_key_id              = local.infrastructure.kms_key_secrets_manager_arn

  tags = merge(local.tags, { Name = var.redis_port_secret_name, Purpose = "redis-credentials" })
}

resource "aws_secretsmanager_secret_version" "redis_port" {
  secret_id = aws_secretsmanager_secret.redis_port.id
  # Port 6380 triggers auto-TLS in Node.js chat service (see pubSub.base.ts:42)
  secret_string = "6380"
}

# Encryption Keys

resource "random_password" "encryption_key_app_repository" {
  keepers = {
    version = "1"
  }
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "encryption_key_app_repository" {
  name                    = var.encryption_key_app_repository_secret_name
  description             = "Encryption key for application repository"
  recovery_window_in_days = var.secrets_recovery_window_days
  kms_key_id              = local.infrastructure.kms_key_secrets_manager_arn

  tags = merge(local.tags, { Name = var.encryption_key_app_repository_secret_name, Purpose = "encryption-key" })
}

resource "aws_secretsmanager_secret_version" "encryption_key_app_repository" {
  secret_id     = aws_secretsmanager_secret.encryption_key_app_repository.id
  secret_string = random_password.encryption_key_app_repository.result
}

resource "random_id" "encryption_key_node_chat_lxm" {
  keepers = {
    version = "1"
  }
  byte_length = 32
}

resource "aws_secretsmanager_secret" "encryption_key_node_chat_lxm" {
  name                    = var.encryption_key_node_chat_lxm_secret_name
  description             = "Encryption key for node chat LXM"
  recovery_window_in_days = var.secrets_recovery_window_days
  kms_key_id              = local.infrastructure.kms_key_secrets_manager_arn

  tags = merge(local.tags, { Name = var.encryption_key_node_chat_lxm_secret_name, Purpose = "encryption-key" })
}

resource "aws_secretsmanager_secret_version" "encryption_key_node_chat_lxm" {
  secret_id     = aws_secretsmanager_secret.encryption_key_node_chat_lxm.id
  secret_string = random_id.encryption_key_node_chat_lxm.hex
}

resource "random_id" "encryption_key_ingestion" {
  keepers = {
    version = "1"
  }
  byte_length = 32
}

resource "aws_secretsmanager_secret" "encryption_key_ingestion" {
  name                    = var.encryption_key_ingestion_secret_name
  description             = "Encryption key for ingestion service"
  recovery_window_in_days = var.secrets_recovery_window_days
  kms_key_id              = local.infrastructure.kms_key_secrets_manager_arn

  tags = merge(local.tags, { Name = var.encryption_key_ingestion_secret_name, Purpose = "encryption-key" })
}

resource "aws_secretsmanager_secret_version" "encryption_key_ingestion" {
  secret_id     = aws_secretsmanager_secret.encryption_key_ingestion.id
  secret_string = random_id.encryption_key_ingestion.hex
}

# Zitadel Secrets

resource "random_password" "zitadel_db_user_password" {
  keepers = {
    version = "1"
  }
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "zitadel_db_user_password" {
  name                    = var.zitadel_db_user_password_secret_name
  description             = "Zitadel database user password"
  recovery_window_in_days = var.secrets_recovery_window_days
  kms_key_id              = local.infrastructure.kms_key_secrets_manager_arn

  tags = merge(local.tags, { Name = var.zitadel_db_user_password_secret_name, Purpose = "zitadel" })
}

resource "aws_secretsmanager_secret_version" "zitadel_db_user_password" {
  secret_id     = aws_secretsmanager_secret.zitadel_db_user_password.id
  secret_string = random_password.zitadel_db_user_password.result
}

resource "random_password" "zitadel_master_key" {
  keepers = {
    version = "1"
  }
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "zitadel_master_key" {
  name                    = var.zitadel_master_key_secret_name
  description             = "Zitadel master key"
  recovery_window_in_days = var.secrets_recovery_window_days
  kms_key_id              = local.infrastructure.kms_key_secrets_manager_arn

  tags = merge(local.tags, { Name = var.zitadel_master_key_secret_name, Purpose = "zitadel" })
}

resource "aws_secretsmanager_secret_version" "zitadel_master_key" {
  secret_id     = aws_secretsmanager_secret.zitadel_master_key.id
  secret_string = random_password.zitadel_master_key.result
}

# Zitadel PAT (placeholder — must be set manually after Zitadel deployment)
resource "aws_secretsmanager_secret" "zitadel_pat" {
  name                    = var.zitadel_pat_secret_name
  description             = "Zitadel Personal Access Token (PAT) - must be set manually"
  recovery_window_in_days = var.secrets_recovery_window_days
  kms_key_id              = local.infrastructure.kms_key_secrets_manager_arn

  tags = merge(local.tags, { Name = var.zitadel_pat_secret_name, Purpose = "zitadel" })
}

resource "aws_secretsmanager_secret_version" "zitadel_pat" {
  secret_id     = aws_secretsmanager_secret.zitadel_pat.id
  secret_string = "<TO BE SET MANUALLY>"

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# RabbitMQ Secrets

resource "random_password" "rabbitmq_password_chat" {
  keepers = {
    version = "1"
  }
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "rabbitmq_password_chat" {
  name                    = var.rabbitmq_password_chat_secret_name
  description             = "RabbitMQ password for chat service"
  recovery_window_in_days = var.secrets_recovery_window_days
  kms_key_id              = local.infrastructure.kms_key_secrets_manager_arn

  tags = merge(local.tags, { Name = var.rabbitmq_password_chat_secret_name, Purpose = "rabbitmq" })
}

resource "aws_secretsmanager_secret_version" "rabbitmq_password_chat" {
  secret_id     = aws_secretsmanager_secret.rabbitmq_password_chat.id
  secret_string = random_password.rabbitmq_password_chat.result
}

# PostgreSQL Database Connection Strings

resource "aws_secretsmanager_secret" "psql_connection_string" {
  for_each = var.postgresql_databases

  name                    = "psql-connection-string-${each.key}"
  description             = "PostgreSQL connection string for ${each.key} database"
  recovery_window_in_days = var.secrets_recovery_window_days
  kms_key_id              = local.infrastructure.kms_key_secrets_manager_arn

  tags = merge(local.tags, { Name = "psql-connection-string-${each.key}", Purpose = "database-credentials" })
}

resource "aws_secretsmanager_secret_version" "psql_connection_string" {
  for_each = var.postgresql_databases

  secret_id     = aws_secretsmanager_secret.psql_connection_string[each.key].id
  secret_string = "postgresql://dbadmin:${random_password.postgres_password.result}@${aws_rds_cluster.postgres.endpoint}:5432/${each.value.name}"
}

# LiteLLM Secrets

resource "random_password" "litellm_proxy_master_key" {
  keepers = {
    version = "1"
  }
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "litellm_proxy_master_key" {
  name                    = var.litellm_proxy_master_key_secret_name
  description             = "LiteLLM proxy master key"
  recovery_window_in_days = var.secrets_recovery_window_days
  kms_key_id              = local.infrastructure.kms_key_secrets_manager_arn

  tags = merge(local.tags, { Name = var.litellm_proxy_master_key_secret_name, Purpose = "litellm" })
}

resource "aws_secretsmanager_secret_version" "litellm_proxy_master_key" {
  secret_id     = aws_secretsmanager_secret.litellm_proxy_master_key.id
  secret_string = random_password.litellm_proxy_master_key.result
}

resource "random_password" "litellm_salt_key" {
  keepers = {
    version = "1"
  }
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "litellm_salt_key" {
  name                    = var.litellm_salt_key_secret_name
  description             = "LiteLLM salt key for hashing"
  recovery_window_in_days = var.secrets_recovery_window_days
  kms_key_id              = local.infrastructure.kms_key_secrets_manager_arn

  tags = merge(local.tags, { Name = var.litellm_salt_key_secret_name, Purpose = "litellm" })
}

resource "aws_secretsmanager_secret_version" "litellm_salt_key" {
  secret_id     = aws_secretsmanager_secret.litellm_salt_key.id
  secret_string = random_password.litellm_salt_key.result
}

# OpenAI endpoint definitions pointing to LiteLLM proxy (Bedrock backend)
# Required by the chat service's Azure SDK factory at startup
resource "aws_secretsmanager_secret" "azure_openai_endpoint_definitions" {
  name                    = var.azure_openai_endpoint_definitions_secret_name
  description             = "OpenAI endpoint definitions pointing to LiteLLM proxy (Bedrock backend)"
  recovery_window_in_days = var.secrets_recovery_window_days
  kms_key_id              = local.infrastructure.kms_key_secrets_manager_arn

  tags = merge(local.tags, { Name = var.azure_openai_endpoint_definitions_secret_name, Purpose = "litellm" })
}

resource "aws_secretsmanager_secret_version" "azure_openai_endpoint_definitions" {
  secret_id = aws_secretsmanager_secret.azure_openai_endpoint_definitions.id
  secret_string = jsonencode([
    {
      endpoint = "http://litellm.unique.svc:4000"
      key      = random_password.litellm_proxy_master_key.result
      location = var.aws_region
      models = [
        { modelName = "gpt-4o", deploymentName = "gpt-4o", modelVersion = "2024-11-20" },
        { modelName = "gpt-4o-2024-11-20", deploymentName = "gpt-4o-2024-11-20", modelVersion = "2024-11-20" },
        { modelName = "gpt-4-turbo", deploymentName = "gpt-4-turbo", modelVersion = "turbo-2024-04-09" },
        { modelName = "gpt-4-32k", deploymentName = "gpt-4-32k", modelVersion = "0613" },
      ]
    }
  ])
}

# S3 Bucket Secrets (for workload discovery via ExternalSecrets)

resource "aws_secretsmanager_secret" "s3_application_data_bucket" {
  name                    = var.s3_application_data_bucket_secret_name
  description             = "S3 bucket name for application data"
  recovery_window_in_days = var.secrets_recovery_window_days
  kms_key_id              = local.infrastructure.kms_key_secrets_manager_arn

  tags = merge(local.tags, { Name = var.s3_application_data_bucket_secret_name, Purpose = "s3-config" })
}

resource "aws_secretsmanager_secret_version" "s3_application_data_bucket" {
  secret_id     = aws_secretsmanager_secret.s3_application_data_bucket.id
  secret_string = aws_s3_bucket.application_data.id
}

resource "aws_secretsmanager_secret" "s3_ai_data_bucket" {
  name                    = var.s3_ai_data_bucket_secret_name
  description             = "S3 bucket name for AI data"
  recovery_window_in_days = var.secrets_recovery_window_days
  kms_key_id              = local.infrastructure.kms_key_secrets_manager_arn

  tags = merge(local.tags, { Name = var.s3_ai_data_bucket_secret_name, Purpose = "s3-config" })
}

resource "aws_secretsmanager_secret_version" "s3_ai_data_bucket" {
  secret_id     = aws_secretsmanager_secret.s3_ai_data_bucket.id
  secret_string = aws_s3_bucket.ai_data.id
}

resource "aws_secretsmanager_secret" "s3_application_data_bucket_arn" {
  name                    = var.s3_application_data_bucket_arn_secret_name
  description             = "S3 bucket ARN for application data"
  recovery_window_in_days = var.secrets_recovery_window_days
  kms_key_id              = local.infrastructure.kms_key_secrets_manager_arn

  tags = merge(local.tags, { Name = var.s3_application_data_bucket_arn_secret_name, Purpose = "s3-config" })
}

resource "aws_secretsmanager_secret_version" "s3_application_data_bucket_arn" {
  secret_id     = aws_secretsmanager_secret.s3_application_data_bucket_arn.id
  secret_string = aws_s3_bucket.application_data.arn
}

resource "aws_secretsmanager_secret" "s3_ai_data_bucket_arn" {
  name                    = var.s3_ai_data_bucket_arn_secret_name
  description             = "S3 bucket ARN for AI data"
  recovery_window_in_days = var.secrets_recovery_window_days
  kms_key_id              = local.infrastructure.kms_key_secrets_manager_arn

  tags = merge(local.tags, { Name = var.s3_ai_data_bucket_arn_secret_name, Purpose = "s3-config" })
}

resource "aws_secretsmanager_secret_version" "s3_ai_data_bucket_arn" {
  secret_id     = aws_secretsmanager_secret.s3_ai_data_bucket_arn.id
  secret_string = aws_s3_bucket.ai_data.arn
}

# RDS CA Certificate Bundle (for SSL connections to Aurora)
# Downloaded from: https://truststore.pki.rds.amazonaws.com/{region}/{region}-bundle.pem

data "http" "rds_ca_bundle" {
  url = "https://truststore.pki.rds.amazonaws.com/${var.aws_region}/${var.aws_region}-bundle.pem"
}

resource "aws_secretsmanager_secret" "rds_ca_bundle" {
  name                    = var.rds_ca_bundle_secret_name
  description             = "RDS CA certificate bundle for ${var.aws_region}"
  recovery_window_in_days = var.secrets_recovery_window_days
  kms_key_id              = local.infrastructure.kms_key_secrets_manager_arn

  tags = merge(local.tags, { Name = var.rds_ca_bundle_secret_name, Purpose = "rds-ssl" })
}

resource "aws_secretsmanager_secret_version" "rds_ca_bundle" {
  secret_id     = aws_secretsmanager_secret.rds_ca_bundle.id
  secret_string = data.http.rds_ca_bundle.response_body
}
