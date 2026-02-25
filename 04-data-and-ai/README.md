# 04-data-and-ai Layer

## Overview

The data-and-ai layer provides data storage, caching, AI services, secrets, and monitoring. Aurora PostgreSQL and ElastiCache Redis run in isolated subnets, S3 buckets enforce VPC-only data access, Bedrock model invocations are logged to CloudWatch, and all secrets are managed with a zero-state-secrets architecture: Terraform manages secret *containers* (name, KMS key, tags), while a post-apply script (`.scripts/seed-secrets.sh`) populates the actual values. No secret values ever appear in Terraform state.

## Design Rationale

### Data Storage

The layer implements three storage tiers:

- **Aurora PostgreSQL** (provisioned mode): Relational data for application services
  - Isolated subnets (no internet access)
  - KMS encryption at rest, SSL/TLS in transit
  - `manage_master_user_password = true` — AWS manages the master password in its own Secrets Manager secret (never in Terraform state)
  - Per-database connection strings populated by seed script as `postgresql://dbadmin:<password>@<endpoint>:5432/<db_name>`
  - Six default databases: `app_repository`, `chat`, `ingestion`, `litellm`, `scope_management`, `theme`

- **ElastiCache Redis**: In-memory caching and pub/sub
  - Isolated subnets, KMS encryption, transit encryption enabled
  - Port 6380 (triggers auto-TLS in Node.js chat service, see `pubSub.base.ts:42`)
  - Slow-log delivery to CloudWatch Logs

- **S3 Buckets**: Object storage for application and AI data
  - `application-data`: Lifecycle transitions to Standard-IA (30d) and Glacier (90d)
  - `ai-data`: Raw AI/ML data
  - Both enforce VPC-only data access via `aws:SourceVpce` Deny policy (management operations exempt for Terraform access)
  - KMS-SSE with bucket keys enabled

### S3 IAM User

The chat service requires static S3 credentials (its `S3BucketStrategy` uses explicit access keys rather than Pod Identity). An IAM user with `kms:Decrypt`, `kms:Encrypt`, and `kms:GenerateDataKey` on the general KMS key provides scoped access to both S3 buckets. Credentials are stored in Secrets Manager.

### AI Services

Amazon Bedrock provides foundation model access:

- **Model access**: Controlled at the organization level via SCPs (not in this layer)
- **Invocation logging**: All model calls logged to CloudWatch Logs (`/bedrock/model-invocations`)
  - Dedicated IAM role with `aws:SourceAccount` and `aws:SourceArn` confused deputy conditions
  - `text_data_delivery_enabled = true` (logs text payloads)
- **VPC endpoint**: Provisioned in the infrastructure layer (Bedrock, Bedrock Runtime)

### Bedrock Inference Profiles

Application inference profiles wrap system-defined profiles or foundation models to provide **per-model cost allocation** (via tags) and **per-model CloudWatch metrics** (invocation count, latency, errors). Workloads invoke via the account-scoped ARN (`arn:aws:bedrock:{region}:{account}:inference-profile/*`).

#### Profile Types

There are three categories of source model, determined by the `source_type` field:

- **`inference-profile`** (EU cross-region): Wraps a system-defined `eu.*` cross-region inference profile. Requests are routed across EU regions for availability and capacity. Data stays within EU but may leave Switzerland.
- **`inference-profile`** (Global): Wraps a system-defined `global.*` inference profile. Used for models that don't have `eu.*` profiles (e.g., Cohere Embed v4). Requests may be routed globally.
- **`foundation-model`** (Swiss-local): Wraps a foundation model natively deployed in `eu-central-2` (Zurich). Data stays in Switzerland. Use these when Swiss data residency is required.

#### Model Availability in eu-central-2 (Zurich)

Foundation models natively available (Swiss data residency):

| Model ID | Provider | Type |
|---|---|---|
| `anthropic.claude-sonnet-4-5-20250929-v1:0` | Anthropic | Text |
| `anthropic.claude-opus-4-5-20251101-v1:0` | Anthropic | Text |
| `anthropic.claude-opus-4-6-v1` | Anthropic | Text |
| `anthropic.claude-haiku-4-5-20251001-v1:0` | Anthropic | Text |
| `anthropic.claude-3-5-sonnet-20240620-v1:0` | Anthropic | Text |
| `anthropic.claude-3-haiku-20240307-v1:0` | Anthropic | Text |
| `cohere.embed-v4:0` | Cohere | Embedding |
| `amazon.titan-embed-text-v2:0` | Amazon | Embedding |

Cross-region inference profiles available from eu-central-2:

| Profile ID | Scope | Name |
|---|---|---|
| `eu.anthropic.claude-sonnet-4-5-20250929-v1:0` | EU | EU Claude Sonnet 4.5 |
| `eu.anthropic.claude-opus-4-5-20251101-v1:0` | EU | EU Claude Opus 4.5 |
| `eu.anthropic.claude-opus-4-6-v1` | EU | EU Claude Opus 4.6 |
| `eu.anthropic.claude-haiku-4-5-20251001-v1:0` | EU | EU Claude Haiku 4.5 |
| `global.cohere.embed-v4:0` | Global | Cohere Embed v4 |

> **Note**: Claude 3.5 Sonnet and Claude 3 Haiku do not have `eu.*` cross-region profiles in eu-central-2. They are only available as Swiss-local foundation models. Cohere Embed v4 requires a `global.*` inference profile for on-demand invocation — it cannot be called directly as a foundation model.

#### Default Application Inference Profiles

| Profile Key | Source Model | Source Type | Data Residency |
|---|---|---|---|
| `claude-sonnet-4-5` | `eu.anthropic.claude-sonnet-4-5-20250929-v1:0` | EU cross-region | EU |
| `claude-opus-4-5` | `eu.anthropic.claude-opus-4-5-20251101-v1:0` | EU cross-region | EU |
| `claude-opus-4-6` | `eu.anthropic.claude-opus-4-6-v1` | EU cross-region | EU |
| `claude-haiku-4-5` | `eu.anthropic.claude-haiku-4-5-20251001-v1:0` | EU cross-region | EU |
| `claude-3-5-sonnet` | `anthropic.claude-3-5-sonnet-20240620-v1:0` | Swiss-local | Switzerland |
| `claude-3-haiku` | `anthropic.claude-3-haiku-20240307-v1:0` | Swiss-local | Switzerland |
| `titan-embed-text-v2` | `amazon.titan-embed-text-v2:0` | Swiss-local | Switzerland |
| `cohere-embed-v4` | `global.cohere.embed-v4:0` | Global | Global |

Profiles are created as `aws_bedrock_inference_profile` resources with the naming convention `{naming-id}-{profile-key}`. Each profile is tagged with `Model = {source-model-id}` for cost allocation. Override the `bedrock_inference_profiles` variable to add, remove, or change profiles per environment.

### LiteLLM Proxy

LiteLLM acts as an OpenAI-compatible proxy in front of Bedrock:

- Master key and salt key generated by the seed script (`openssl rand`)
- `azure-openai-endpoint-definitions` secret contains a JSON array pointing to `http://litellm.unique.svc:4000` with model mappings (gpt-4o, gpt-4-turbo, gpt-4-32k)
- Required by the chat service's Azure SDK factory at startup

### Monitoring

- **Managed Prometheus**: Metrics collection workspace, IAM-gated (SigV4), VPC endpoint in infrastructure layer
- **Managed Grafana** (optional): SAML auth, VPC-only access via `vpc_configuration` on private subnets
  - Data sources: Prometheus (scoped to workspace ARN) and CloudWatch (scoped to account/region)
  - ENI management policy for VPC placement (`ec2:*NetworkInterface*`, region-scoped)
  - Disabled in `eu-central-2` (not available)

### Secrets Strategy

**Hybrid approach — no generated credentials in Terraform state.**

- **Infrastructure facts** (endpoints, ports, bucket names, ARNs, CA certs) are managed as `aws_secretsmanager_secret_version` by Terraform — always in sync with actual resources, not sensitive.
- **Generated credentials** (passwords, encryption keys, IAM access keys) are populated by `.scripts/seed-secrets.sh` after `terraform apply` — never in Terraform state.
- **Aurora master password** is managed by AWS itself (`manage_master_user_password = true`), read by the seed script from the AWS-managed secret.

The seed script:

- Reads the Aurora master password from the AWS-managed secret
- Generates passwords and encryption keys via `openssl rand`
- Creates IAM access keys via `aws iam create-access-key`
- Builds LiteLLM endpoint definitions JSON with the generated master key
- Is **idempotent**: skips secrets that already have values (use `--force` to overwrite)

Applications retrieve secrets via ExternalSecrets -> Secrets Manager -> KMS (Secrets Manager key from infrastructure layer).

| Category | Secrets | Managed By |
|----------|---------|------------|
| PostgreSQL | `psql-host`, `psql-port`, `psql-username` | Terraform |
| PostgreSQL | `psql-password`, `psql-connection-string-{db}` | Seed script |
| Redis | `redis-host`, `redis-port` | Terraform |
| Encryption keys | `encryption-key-app-repository`, `encryption-key-node-chat-lxm`, `encryption-key-ingestion` | Seed script |
| Zitadel | `zitadel-db-user-password`, `zitadel-master-key`, `manual-zitadel-scope-mgmt-pat` | Seed script |
| RabbitMQ | `rabbitmq-password-chat` | Seed script |
| LiteLLM | `litellm-proxy-master-key`, `litellm-salt-key`, `azure-openai-endpoint-definitions` | Seed script |
| S3 config | `s3-application-data-bucket`, `s3-ai-data-bucket`, `s3-*-bucket-arn`, `s3-endpoint`, `s3-region` | Terraform |
| S3 credentials | `s3-access-key-id`, `s3-secret-access-key` | Seed script |
| RDS SSL | `rds-ca-bundle` | Terraform |

## Resources

### Aurora PostgreSQL

- **Cluster**: Provisioned mode, engine 14.19, `dbadmin` master user, `manage_master_user_password = true`
- **Instances**: Configurable count and instance class (default: 2x `db.r6g.large`, sbx: 1x `db.t4g.medium`)
- **Subnet Group**: Isolated subnets
- **Security Group**: PostgreSQL (5432) from VPC CIDR, egress to VPC CIDR
- **CloudWatch Logs**: PostgreSQL log exports enabled

### ElastiCache Redis

- **Replication Group**: Redis 7.1, port 6380 (auto-TLS), configurable node count
- **Parameter Group**: `redis7` family
- **Subnet Group**: Isolated subnets
- **Security Group**: Port 6380 from VPC CIDR, egress to VPC CIDR
- **CloudWatch Log Group**: Slow-log in JSON format, encrypted with CloudWatch Logs KMS key

### S3 Buckets

- **Application Data**: Versioned, KMS-SSE, public access blocked, lifecycle (IA 30d, Glacier 90d)
- **AI Data**: Versioned, KMS-SSE, public access blocked
- **Bucket Policies**: `Deny` all data operations unless `aws:SourceVpce` matches S3 Gateway Endpoint

### Bedrock

- **Application Inference Profiles**: 8 profiles (4 EU cross-region Anthropic + 3 Swiss-local foundation models + 1 global embedding)
- **Logging Configuration**: Account-level, CloudWatch Logs destination, text delivery enabled
- **IAM Role**: `bedrock.amazonaws.com` service principal with confused deputy conditions
- **CloudWatch Log Group**: Encrypted with CloudWatch Logs KMS key
- **Foundation Models Data Source**: Amazon provider models (exposed in outputs)

### Managed Prometheus

- **Workspace**: Logging to infrastructure layer CloudWatch log group

### Managed Grafana (Optional)

- **Workspace**: SAML auth, `CURRENT_ACCOUNT` scope, Prometheus + CloudWatch data sources
- **VPC Configuration**: Private subnets, dedicated security group (HTTPS egress to VPC)
- **IAM Role**: 3 policies — VPC ENI management, Prometheus read, CloudWatch read

### Secrets Manager

- **30+ secret containers**: All encrypted with Secrets Manager KMS key from infrastructure layer
- **Recovery Window**: Configurable (default 30 days, sbx: 0 for immediate deletion)
- **Values**: Populated by `.scripts/seed-secrets.sh` (not in Terraform state)

### VPC Endpoints

- **Aurora**: `com.amazonaws.{region}.rds` Interface Endpoint (Aurora uses RDS API)
- **ElastiCache**: `com.amazonaws.{region}.elasticache` Interface Endpoint
- Both use the shared VPC endpoints security group from infrastructure layer

### IAM (All policies use `aws_iam_policy_document`)

- **Bedrock Logging Role**: `logs:CreateLogStream`, `logs:PutLogEvents` on Bedrock log group
- **Grafana Role**: VPC ENI management + Prometheus read + CloudWatch read
- **S3 Access User**: `s3:Get/Put/Delete/List` on both buckets + `kms:Decrypt/Encrypt/GenerateDataKey`

## Security Principles

### Encryption

- **At Rest**: All data encrypted with customer-managed KMS keys from infrastructure layer
  - Aurora, ElastiCache, S3: General purpose KMS key
  - CloudWatch Logs: Dedicated CloudWatch Logs KMS key
  - Secrets Manager: Dedicated Secrets Manager KMS key
  - Performance Insights: General purpose KMS key (when enabled)
- **In Transit**: SSL/TLS enforced for Aurora, Redis (port 6380 auto-TLS), S3 (HTTPS)

### Network Isolation

- **Databases**: Aurora and ElastiCache in isolated subnets (no internet, no NAT)
- **S3 Bucket Policies**: Deny data operations unless via S3 Gateway Endpoint
- **Grafana**: VPC-only access via `vpc_configuration` on private subnets
- **Prometheus**: IAM-gated (SigV4), VPC endpoint in infrastructure layer
- **Security Groups**: All restricted to VPC CIDR (no `0.0.0.0/0`)

### Access Control

- **IAM Policies**: All use `aws_iam_policy_document` data sources (validated at plan time)
- **Bedrock**: Confused deputy protection (`aws:SourceAccount`, `aws:SourceArn`)
- **Grafana VPC ENI**: Region-scoped (`aws:RequestedRegion`)
- **Provider Guard**: `allowed_account_ids` prevents cross-account deployment

## Deployment

### Prerequisites

1. Infrastructure layer deployed (provides VPC, KMS keys, subnets, VPC endpoints)
2. `common.auto.tfvars` configured at repository root
3. Environment-specific configuration in `environments/{env}/00-config.auto.tfvars`

### Configuration

Key configuration options (defaults shown, override per environment):

```hcl
# Aurora
aurora_instance_class      = "db.r6g.large"   # sbx: db.t4g.medium
aurora_instance_count      = 2                 # sbx: 1
aurora_deletion_protection = true              # sbx: false
aurora_skip_final_snapshot = false             # sbx: true

# ElastiCache
elasticache_node_type                  = "cache.r7g.large"  # sbx: cache.t3.micro
elasticache_num_cache_nodes            = 2                  # sbx: 1
elasticache_automatic_failover_enabled = true               # sbx: false
elasticache_multi_az_enabled           = true               # sbx: false

# Feature Flags
enable_managed_prometheus = true
enable_managed_grafana    = true   # sbx: false (not available in eu-central-2)
enable_bedrock_logging    = true

# VPC Endpoints
enable_aurora_endpoint      = true
enable_elasticache_endpoint = true

# Secrets
secrets_recovery_window_days = 30  # sbx: 0
```

### Deployment Steps

**Recommended** (deploys infrastructure + seeds secrets in one step):

```bash
.scripts/deploy-data-and-ai.sh <environment> [--auto-approve] [--skip-plan]
```

**Manual** (two steps):

```bash
# Step 1: Deploy infrastructure
./scripts/deploy.sh data-and-ai <environment>

# Step 2: Seed secret values
.scripts/seed-secrets.sh <environment>
```

**Environments**: `dev`, `test`, `prod`, `sbx`

**Options**:
- `--auto-approve`: Skip interactive confirmation
- `--skip-plan`: Skip the plan step and apply directly
- `--force` (seed-secrets.sh only): Overwrite existing secret values

### Post-Deployment

1. Verify Aurora cluster endpoint is resolvable from private subnets
2. Test ElastiCache connectivity on port 6380
3. Set `manual-zitadel-scope-mgmt-pat` secret manually after Zitadel deployment
4. Configure Grafana SAML authentication (if enabled)
5. Verify zero secrets in state: `terraform state pull | grep -c '"secret_string"'` returns 0

## Outputs

### Managed Prometheus
- `prometheus_workspace_id`, `prometheus_workspace_arn`, `prometheus_workspace_endpoint`

### Managed Grafana
- `grafana_workspace_id`, `grafana_workspace_endpoint`, `grafana_iam_role_arn`

### S3 Buckets
- `s3_bucket_application_data_id`, `s3_bucket_application_data_arn`
- `s3_bucket_ai_data_id`, `s3_bucket_ai_data_arn`

### Aurora PostgreSQL
- `aurora_cluster_id`, `aurora_cluster_arn`
- `aurora_cluster_endpoint`, `aurora_cluster_reader_endpoint`, `aurora_cluster_database_name`
- `aurora_master_user_secret_arn` (AWS-managed password secret)

### ElastiCache Redis
- `elasticache_replication_group_id`
- `elasticache_configuration_endpoint_address`, `elasticache_primary_endpoint_address`, `elasticache_port`

### IAM
- `s3_access_iam_user_name`

### Seed Script Support
- `aws_region`, `postgresql_databases`
- `secret_arns` (consolidated map of all 25 secret ARNs)
- `psql_connection_string_secret_arns` (map of database key to connection string secret ARN)

### VPC Endpoints
- `aurora_endpoint_id`, `elasticache_endpoint_id`

### Bedrock
- `bedrock_inference_profile_arns` (map of profile key to account-scoped ARN)
- `bedrock_available_models`

## References

- [Aurora PostgreSQL Best Practices](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.BestPractices.html)
- [ElastiCache Best Practices](https://docs.aws.amazon.com/AmazonElastiCache/latest/red-ug/best-practices.html)
- [Amazon Bedrock Model Invocation Logging](https://docs.aws.amazon.com/bedrock/latest/userguide/model-invocation-logging.html)
- [Amazon Managed Prometheus](https://docs.aws.amazon.com/prometheus/latest/userguide/what-is-Amazon-Managed-Service-Prometheus.html)
- [Amazon Managed Grafana](https://docs.aws.amazon.com/grafana/latest/userguide/what-is-Amazon-Managed-Grafana.html)
- [S3 VPC Endpoint Policies](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints-s3.html)
