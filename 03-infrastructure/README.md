# 03-infrastructure Layer

## Overview

The infrastructure layer provides the foundational networking and compute infrastructure including VPC, subnets, NAT Gateways, VPC endpoints, KMS keys, Secrets Manager, monitoring alarms, and an optional management server. This layer establishes the network foundation that all other layers depend on.

## Design Rationale

### Network Architecture

The infrastructure layer implements a **four-tier subnet architecture** following AWS best practices, with right-sized CIDRs per role:

- **Public Subnets** (`/28`, 16 IPs): Host NAT Gateways only
  - Minimal footprint — no workloads, no public IPs on launch
  - EKS load balancers are internal and use private subnets

- **Private Subnets** (`/22`, 1024 IPs): Host workloads (EKS nodes, compute, AI services, monitoring)
  - Outbound internet access via NAT Gateway
  - Network segmentation via Security Groups and NACLs
  - Tagged for EKS cluster discovery (`kubernetes.io/cluster/<name>` and `kubernetes.io/role/internal-elb`)

- **Isolated Subnets** (`/26`, 64 IPs): Host databases (RDS, ElastiCache)
  - No internet access (no NAT Gateway route)
  - Maximum security for data stores
  - Direct access only from private subnets via security groups

- **GitHub Runner Subnets** (`/26`, 64 IPs): Host self-hosted GitHub Actions runners
  - Conditional on `github_runners_enabled`
  - Associated with private route tables only when NAT Gateway is enabled

An optional **secondary CIDR** (`100.64.0.0/20`, RFC 6598) can be enabled for EKS pod networking, keeping pod IPs separate from node IPs.

### CIDR Allocation

Subnet sizes are computed dynamically from the VPC prefix length so the layout is portable across VPC sizes (default `/19`):

| Subnet   | Size | IPs   | `cidrsubnet` start | Example (10.1.0.0/19)        |
|----------|------|-------|---------------------|------------------------------|
| Private  | /22  | 1024  | 0                   | 10.1.0.0, 10.1.4.0, 10.1.8.0 |
| Public   | /28  | 16    | 192                 | 10.1.12.0, 10.1.12.16, 10.1.12.32 |
| Isolated | /26  | 64    | 64                  | 10.1.16.0, 10.1.16.64, 10.1.16.128 |
| Runners  | /26  | 64    | 80                  | 10.1.20.0, 10.1.20.64, 10.1.20.128 |

All ranges are verified non-overlapping. The `newbits` values are derived as `desired_prefix - vpc_prefix_length`, so changing the VPC CIDR size preserves subnet sizes automatically.

### VPC Flow Logs

All VPC traffic is captured via Flow Logs sent to a dedicated CloudWatch Log Group (`/vpc-flow-logs`), encrypted with the CloudWatch Logs KMS key. Aggregation interval is 60 seconds for near-real-time visibility.

### Default Security Group

The VPC default security group is locked down with **no ingress or egress rules** (deny all), tagged `DO-NOT-USE`, preventing accidental use.

### VPC Endpoints

VPC endpoints provide **private connectivity** to AWS services without internet access:

- **Gateway Endpoints**: S3 (free, with restrictive policy scoped to Terraform state bucket and ECR layer bucket)
- **Interface Endpoints**: SSM, SSM Messages, EC2 Messages, Secrets Manager, ECR API, ECR DKR, CloudWatch Logs, CloudWatch Metrics, Prometheus, Bedrock, Bedrock Runtime, STS, KMS, EC2
- **Private Access**: All AWS service access stays within the VPC

The S3 gateway endpoint is associated with all route tables (public, private, and isolated) regardless of NAT Gateway status.

### Management Server

An optional EC2 management server provides:

- **Secure Access**: Via AWS Systems Manager Session Manager (no SSH keys required)
- **VPC-Only Egress**: Security group restricts all outbound to VPC CIDR only — no internet egress
- **Golden AMI**: User-data stripped to hostname-only; all tools (kubectl, helm, terraform, eksctl, gh, docker) must be pre-baked into the AMI
- **Scoped IAM**: EKS access restricted to clusters matching this product's naming pattern (`<naming-id>-*`)

### Monitoring and Alerting

- **SNS Topic**: Encrypted with general KMS key, supports email subscriptions via `alert_email_endpoints`
- **NAT Gateway Alarms**: `ErrorPortAllocation` and `PacketsDropCount` per gateway, wired to SNS
- **NAT HA Guard**: `check` block warns if `single_nat_gateway = true` in production

## Resources

### VPC and Networking

- **VPC**: Main VPC with DNS support, optional secondary CIDR for EKS pods
- **Default Security Group**: Locked down (deny all)
- **VPC Flow Logs**: CloudWatch-backed, 60s aggregation, KMS-encrypted
- **Internet Gateway**: Provides internet access for NAT Gateways
- **NAT Gateways**: Configurable — one per AZ or single (with HA guard for prod)
- **Subnets**: Right-sized per tier (public /28, private /22, isolated /26, runners /26)
- **Route Tables**: Always created for all tiers; NAT route added conditionally

### VPC Endpoints

- **Interface Endpoints**: SSM, Secrets Manager, ECR (API + DKR), CloudWatch (Logs + Metrics), Prometheus, Bedrock, Bedrock Runtime, STS, KMS, EC2, EC2 Messages, SSM Messages
- **Gateway Endpoints**: S3 (with restrictive bucket-scoped policy)
- **Security Group**: Restricted ingress/egress to VPC CIDR

### KMS Keys

- **General Purpose Key**: EKS, EBS, S3, RDS, ElastiCache, ECR, SNS (with `kms:CreateGrant` for EC2 and RDS)
- **Secrets Manager Key**: Secrets Manager + ECR Pull Through Cache
- **CloudWatch Logs Key**: CloudWatch Log Groups
- **Prometheus Key** (optional): Managed Prometheus workspace

### EBS Encryption

- **EBS Encryption by Default**: Enabled account-wide
- **Default KMS Key**: Set to general purpose key

### Secrets Manager

- **KMS Key**: Dedicated encryption key for Secrets Manager (used by downstream layers)
- **VPC Endpoint**: Private access to Secrets Manager from private subnets

### Management Server (Optional)

- **EC2 Instance**: Pre-baked golden AMI (Amazon Linux 2023 base fallback)
- **IAM Role**: SSM access + scoped EKS cluster access
- **Security Group**: VPC-only ingress and egress (no internet)
- **IMDSv2**: Enforced for enhanced security

### Monitoring

- **Infrastructure Log Group**: Centralized logging, 365-day retention (except sandbox)
- **VPC Flow Log Group**: Dedicated, retention matches `cloudwatch_log_retention_days`
- **SNS Topic**: KMS-encrypted alerts topic
- **CloudWatch Alarms**: NAT Gateway port allocation errors and packet drops

### GitHub Runners (Optional)

- **Subnets**: /26 per AZ, non-overlapping with other tiers
- **Security Group**: HTTPS outbound to internet + VPC endpoints
- **IAM Role**: Prepared for CodeBuild-based runners (resource provisioned separately)
- **Route Table Guard**: Association only created when NAT Gateway is enabled

## Security Principles

### Network Security

- **VPC Flow Logs**: All traffic captured for audit and incident response
- **Default SG Locked**: No accidental use of default security group
- **Private Subnets**: Workloads in private subnets (no public IPs)
- **Isolated Subnets**: Databases with no internet access
- **VPC-Only Management Server**: No internet egress from jump server
- **S3 Endpoint Policy**: Scoped to Terraform state and ECR layer buckets only

### Encryption

- **KMS Keys**: Customer-managed keys for all encryption
- **EBS Encryption by Default**: All new volumes automatically encrypted
- **KMS CreateGrant**: EC2 and RDS can create grants (conditioned on `kms:GrantIsForAWSResource`)
- **Secrets Manager**: Dedicated KMS key
- **CloudWatch Logs**: All log groups encrypted at rest
- **SNS Topic**: Encrypted with general KMS key

### Access Control

- **Provider Guard**: `allowed_account_ids` prevents cross-account mistakes
- **Scoped IAM**: Management server EKS access restricted to product clusters
- **VPC Endpoints**: Private access to AWS services
- **IMDSv2**: Enforced on all EC2 instances

### Audit and Compliance

- **VPC Flow Logs**: Always enabled, 60s aggregation
- **CloudWatch Logs**: All infrastructure operations logged
- **365-Day Retention**: Enforced for non-sandbox environments
- **Terraform Version**: Pinned to `>= 1.10.0` (native S3 locking)
- **AWS Provider**: Pinned to `~> 5.100`

## Well-Architected Framework

### Operational Excellence

- **Automated Deployment**: Infrastructure defined as code
- **Monitoring**: CloudWatch alarms for NAT Gateway health, SNS alerting
- **VPC Flow Logs**: Near-real-time network visibility
- **Golden AMI**: Repeatable, auditable management server builds

### Security

- **Network Isolation**: Four-tier subnet architecture with right-sized CIDRs
- **Encryption**: All data encrypted at rest (KMS) and in transit (TLS via endpoints)
- **Default Deny**: Default SG locked, VPC-only management server egress
- **Provider Guard**: `allowed_account_ids` prevents cross-account deployment
- **Scoped IAM**: Least privilege for all roles

### Reliability

- **Multi-AZ Deployment**: Subnets and NAT Gateways across availability zones
- **NAT HA Guard**: Warning when production uses single NAT Gateway
- **Always-On Route Tables**: Private route tables created unconditionally
- **Monitoring Alarms**: NAT Gateway health alerts via SNS

### Performance Efficiency

- **VPC Endpoints**: Private connectivity reduces latency
- **Right-Sized Subnets**: CIDRs matched to actual requirements
- **Secondary CIDR**: Optional dedicated IP range for EKS pod networking
- **EBS Optimization**: Enabled on management server

### Cost Optimization

- **Right-Sized VPC**: `/19` (8,192 IPs) instead of `/16` (65,536 IPs)
- **Right-Sized Subnets**: /28 public, /22 private, /26 isolated/runners
- **Gateway Endpoints**: Free S3 access
- **Single NAT Option**: Available for non-production environments
- **Configurable Retention**: Shorter log retention for sandbox

## Deployment

### Prerequisites

1. Bootstrap layer must be deployed first
2. Governance layer should be deployed (optional but recommended)
3. `common.auto.tfvars` configured at repository root
4. Environment-specific configuration in `environments/{env}/00-config.auto.tfvars`

### Configuration

Key configuration options:

```hcl
# VPC Configuration
vpc_cidr              = "10.1.0.0/19"
secondary_cidr_enabled = true  # 100.64.0.0/20 for EKS pods

# NAT Gateway
enable_nat_gateway = true
single_nat_gateway = true  # Single NAT for non-prod (HA guard warns in prod)

# Management Server
management_server_enabled        = true
management_server_ami           = ""      # Use golden AMI ID here
management_server_instance_type = "t3.medium"
management_server_public_access = false   # Session Manager only

# GitHub Runners
github_runners_enabled = true

# Monitoring
alert_email_endpoints = ["ops@example.com"]

# VPC Endpoints
ssm_endpoints_enabled            = true
enable_secrets_manager_endpoint = true
enable_bedrock_endpoint         = true

# Route 53 Private Hosted Zone (uncomment and set before deploying)
# These values come from your landing zone or connectivity account
# route53_private_zone_domain = "sbx.example.com"
# route53_private_zone_id     = "ZXXXXXXXXXXXXXXXXX"
```

> **Note**: The Route 53 private zone values (`route53_private_zone_domain` and `route53_private_zone_id`) are commented out by default. If your deployment uses a Route 53 Private Hosted Zone (e.g., from a connectivity account in a hub-and-spoke topology), uncomment and set these values in `environments/{env}/00-config.auto.tfvars` before deploying. Without them, the VPC association with the private hosted zone is skipped.

### Deployment Steps

```bash
./scripts/deploy.sh infrastructure <environment>
```

**Environments**: `dev`, `test`, `prod`, `sbx`

**Options**:
- `--auto-approve`: Skip interactive confirmation
- `--skip-plan`: Skip the plan step and apply directly

### Post-Deployment

After deployment:

1. Verify VPC and subnets are created correctly
2. Test VPC endpoint connectivity (e.g., SSM, Secrets Manager)
3. Verify VPC Flow Logs are delivering to CloudWatch
4. Check NAT Gateway alarms are in OK state

## Outputs

### VPC
- `vpc_id`, `vpc_cidr_block`, `vpc_arn`
- `vpc_flow_log_id`, `vpc_flow_log_group_name`

### Subnets
- `public_subnet_ids`, `public_subnet_cidrs`
- `private_subnet_ids`, `private_subnet_cidrs`
- `isolated_subnet_ids`, `isolated_subnet_cidrs`

### Networking
- `internet_gateway_id`
- `nat_gateway_ids`, `nat_gateway_public_ips`
- `public_route_table_id`, `private_route_table_ids`, `isolated_route_table_ids`
- `availability_zones`, `aws_region`, `aws_account_id`

### VPC Endpoints
- `s3_gateway_endpoint_id`, `kms_endpoint_id`, `secrets_manager_endpoint_id`
- `ecr_api_endpoint_id`, `ecr_dkr_endpoint_id`
- `cloudwatch_logs_endpoint_id`, `cloudwatch_metrics_endpoint_id`
- `prometheus_endpoint_id`, `bedrock_endpoint_id`, `bedrock_runtime_endpoint_id`
- `sts_endpoint_id`, `ec2_endpoint_id`
- `ssm_endpoint_id`, `ssm_messages_endpoint_id`, `ec2_messages_endpoint_id`
- `vpc_endpoints_security_group_id`

### KMS
- `kms_key_general_arn`, `kms_key_general_id`
- `kms_key_secrets_manager_arn`, `kms_key_secrets_manager_id`
- `kms_key_cloudwatch_logs_arn`, `kms_key_cloudwatch_logs_id`
- `kms_key_prometheus_arn`, `kms_key_prometheus_id`

### Monitoring
- `sns_topic_alerts_arn`
- `cloudwatch_log_group_infrastructure_name`, `cloudwatch_log_group_infrastructure_arn`

### Management Server
- `management_server_instance_id`, `management_server_private_ip`, `management_server_public_ip`
- `management_server_security_group_id`
- `ssm_instance_profile_arn`, `ssm_instance_profile_name`, `ssm_instance_role_arn`

### DNS
- `route53_private_zone_id`, `route53_private_zone_domain`

## References

- [AWS VPC Best Practices](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-best-practices.html)
- [VPC Endpoints](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints.html)
- [VPC Flow Logs](https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs.html)
- [AWS Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [AWS Well-Architected Framework - Security](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/welcome.html)
- [EBS Encryption by Default](https://docs.aws.amazon.com/ebs/latest/userguide/encryption-by-default.html)
- [IMDSv2 Best Practices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-instance-metadata-service.html)
