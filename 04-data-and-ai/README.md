# 04-data-and-ai Layer

## Overview

The data-and-ai layer provides data storage, AI services, and monitoring infrastructure including Aurora PostgreSQL, ElastiCache Redis, S3 buckets, Amazon Bedrock, Managed Prometheus, and Managed Grafana. This layer establishes the data foundation and AI capabilities for applications.

## Design Rationale

### Data Architecture

The data layer implements a **multi-tier data storage strategy**:

- **Relational Data**: Aurora PostgreSQL for structured data
  - Multi-AZ deployment for high availability
  - Automated backups and point-in-time recovery
  - Isolated subnets for maximum security

- **Caching**: ElastiCache Redis for high-performance caching
  - Cluster mode for high availability
  - Isolated subnets for security
  - Automatic failover

- **Object Storage**: S3 buckets for unstructured data
  - Application data bucket
  - AI/ML data bucket with Bedrock logging support
  - Lifecycle policies for cost optimization

### AI Services

Amazon Bedrock provides **foundation model access** with:

- **Private Access**: Via VPC endpoint (no internet required)
- **Model Access Control**: Configurable via SCPs at organization level
- **Logging**: Invocation logs stored in S3 for audit and compliance
- **Regional Availability**: Bedrock available in eu-central-2 (Zurich)

### Monitoring Architecture

Separate monitoring services for different purposes:

- **Infrastructure Monitoring**: CloudWatch Logs (in infrastructure layer)
- **Application Monitoring**: Managed Prometheus and Grafana (in this layer)
  - Prometheus for metrics collection
  - Grafana for visualization
  - Integration with CloudWatch for comprehensive observability

### Security-First Design

All data resources follow security best practices:

- **Isolated Subnets**: Databases in isolated subnets with no internet access
- **KMS Encryption**: All data encrypted at rest with customer-managed keys
- **Security Groups**: Restricted access from private subnets only
- **Private Endpoints**: VPC endpoints for private access to AWS services

## Resources

### Aurora PostgreSQL

- **Cluster**: Multi-AZ Aurora PostgreSQL cluster
  - Automated backups enabled
  - Point-in-time recovery
  - Isolated subnet deployment
  - KMS encryption at rest
  - Security group restricted to private subnets

### ElastiCache Redis

- **Cluster**: Redis cluster mode for high availability
  - Automatic failover
  - Isolated subnet deployment
  - KMS encryption at rest
  - Security group restricted to private subnets

### S3 Buckets

- **Application Data Bucket**: For application data storage
  - Versioning enabled
  - KMS encryption at rest
  - Lifecycle policies (transition to IA and Glacier)
  - Public access blocked

- **AI Data Bucket**: For AI/ML data and Bedrock logs
  - Versioning enabled
  - KMS encryption at rest
  - Bedrock logging policy
  - Public access blocked

### Amazon Bedrock

- **Model Access Configuration**: Foundation model access
  - Private access via VPC endpoint
  - Logging to S3 bucket
  - Model access controlled via SCPs (organization level)

### Managed Prometheus

- **Workspace**: For metrics collection from EKS and applications
  - KMS encryption at rest
  - Logging to CloudWatch
  - Integration with Grafana

### Managed Grafana

- **Workspace**: For metrics and logs visualization
  - SAML authentication
  - Data sources: Prometheus and CloudWatch
  - Account-scoped access
  - IAM policies restricted to account resources

### Secrets

- **Database Credentials**: Stored in AWS Secrets Manager
  - Automatic rotation support
  - KMS encryption
  - Access via VPC endpoint

## Security Principles

### Data Encryption

- **At Rest**: All data encrypted with customer-managed KMS keys
  - Aurora: KMS encryption for database storage
  - ElastiCache: KMS encryption for Redis data
  - S3: KMS encryption for all objects
  - Prometheus: KMS encryption for workspace
  - Secrets: KMS encryption in Secrets Manager

- **In Transit**: All connections encrypted
  - Aurora: SSL/TLS for database connections
  - ElastiCache: TLS for Redis connections
  - S3: HTTPS-only access (enforced by bucket policy)

### Network Security

- **Isolated Subnets**: Databases in isolated subnets with no internet access
- **Security Groups**: Restricted ingress from private subnets only
- **VPC Endpoints**: Private access to AWS services (Secrets Manager, S3)
- **No Public Access**: All resources are private by default

### Access Control

- **IAM Policies**: Least privilege access for Grafana and Prometheus
- **Security Groups**: Database access restricted to application subnets
- **Secrets Manager**: Access via IAM roles and VPC endpoints
- **Bedrock**: Access controlled via SCPs at organization level

### Audit and Compliance

- **Bedrock Logging**: All model invocations logged to S3
- **CloudWatch Logs**: Prometheus workspace logs
- **S3 Access Logging**: Can be enabled for audit trails
- **Database Backups**: Automated backups for compliance

## Well-Architected Framework

### Operational Excellence

- **Automated Backups**: Aurora automated backups and point-in-time recovery
- **Monitoring**: Prometheus and Grafana for application metrics
- **Logging**: Comprehensive logging for AI services and databases
- **Documentation**: Clear data architecture and security design

### Security

- **Encryption**: All data encrypted at rest and in transit
- **Network Isolation**: Databases in isolated subnets
- **Access Control**: Least privilege IAM policies and security groups
- **Secrets Management**: Secure storage in Secrets Manager
- **Private Access**: VPC endpoints for AWS service access

### Reliability

- **Multi-AZ Deployment**: Aurora and ElastiCache across availability zones
- **High Availability**: Automatic failover for databases and cache
- **Backup and Recovery**: Automated backups and point-in-time recovery
- **Monitoring**: Prometheus and Grafana for observability

### Performance Efficiency

- **ElastiCache**: High-performance caching reduces database load
- **Aurora**: Serverless v2 for automatic scaling
- **S3 Lifecycle**: Automatic transition to cheaper storage classes
- **VPC Endpoints**: Private connectivity reduces latency

### Cost Optimization

- **S3 Lifecycle Policies**: Automatic transition to IA and Glacier
- **Aurora Serverless v2**: Pay only for what you use
- **ElastiCache**: Right-sized clusters for cost efficiency
- **Monitoring**: Managed services reduce operational overhead

## Deployment

### Prerequisites

1. Infrastructure layer must be deployed first
2. `common.auto.tfvars` configured at repository root
3. Environment-specific configuration in `environments/{env}/00-config.auto.tfvars`

### Configuration

Key configuration options:

```hcl
# Aurora Configuration
enable_aurora = true
aurora_engine_version = "15.4"
aurora_instance_class = "db.serverless"
aurora_database_name = "appdb"

# ElastiCache Configuration
enable_elasticache = true
elasticache_node_type = "cache.t3.medium"
elasticache_num_cache_nodes = 3

# Bedrock Configuration
enable_bedrock_logging = true

# Monitoring
enable_managed_prometheus = true
enable_managed_grafana = true
```

### Deployment Steps

```bash
./scripts/deploy.sh data-and-ai <environment>
```

**Environments**: `dev`, `test`, `prod`, `sbx`

**Options**:
- `--auto-approve`: Skip interactive confirmation
- `--skip-plan`: Skip the plan step and apply directly

### Post-Deployment

After deployment:

1. Verify Aurora cluster is accessible from private subnets
2. Test ElastiCache connectivity
3. Configure Grafana authentication (SAML)
4. Verify Bedrock model access (if configured)

## Outputs

- `aurora_cluster_endpoint`: Aurora cluster endpoint
- `aurora_cluster_reader_endpoint`: Aurora reader endpoint
- `elasticache_endpoint`: ElastiCache Redis endpoint
- `s3_application_data_bucket`: Application data S3 bucket name
- `s3_ai_data_bucket`: AI data S3 bucket name
- `bedrock_workspace_id`: Bedrock workspace ID (if enabled)
- `prometheus_workspace_id`: Prometheus workspace ID (if enabled)
- `grafana_workspace_id`: Grafana workspace ID (if enabled)

## Notes

### Bedrock Model Access

Bedrock model access is controlled at the **organization level** via Service Control Policies (SCPs). To restrict models, configure an SCP with NotResource pattern. See the Bedrock Terraform file for an example SCP configuration.

### Database Credentials

Database credentials are stored in AWS Secrets Manager. Applications should retrieve credentials via IAM roles and VPC endpoints. Automatic rotation can be configured for enhanced security.

### Monitoring Services

Prometheus and Grafana are **application monitoring** tools, not infrastructure monitoring. Infrastructure monitoring (VPC Flow Logs, etc.) is handled by CloudWatch Logs in the infrastructure layer.

## References

- [Amazon Aurora Best Practices](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.BestPractices.html)
- [ElastiCache Best Practices](https://docs.aws.amazon.com/AmazonElastiCache/latest/red-ug/best-practices.html)
- [Amazon Bedrock Documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/what-is-bedrock.html)
- [Amazon Managed Prometheus](https://docs.aws.amazon.com/prometheus/latest/userguide/what-is-Amazon-Managed-Service-Prometheus.html)
- [Amazon Managed Grafana](https://docs.aws.amazon.com/grafana/latest/userguide/what-is-Amazon-Managed-Grafana.html)
- [AWS Well-Architected Framework - Security](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/welcome.html)

