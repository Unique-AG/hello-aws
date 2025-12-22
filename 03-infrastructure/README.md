# 03-infrastructure Layer

## Overview

The infrastructure layer provides the foundational networking and compute infrastructure including VPC, subnets, NAT Gateways, VPC endpoints, KMS keys, Secrets Manager, and an optional management server. This layer establishes the network foundation that all other layers depend on.

## Design Rationale

### Network Architecture

The infrastructure layer implements a **three-tier subnet architecture** following AWS best practices:

- **Public Subnets**: Host NAT Gateways (one per AZ for high availability)
  - EKS load balancers are internal and use private subnets
  - Public subnets are minimal and only for NAT Gateway infrastructure

- **Private Subnets**: Host workloads (EKS, compute, AI services, monitoring)
  - Outbound internet access via NAT Gateway
  - Network segmentation via Security Groups and NACLs
  - Internal load balancers for EKS services

- **Isolated Subnets**: Host databases (RDS, ElastiCache)
  - No internet access (no NAT Gateway route)
  - Maximum security for data stores
  - Direct access only from private subnets via security groups

### Network Segmentation Strategy

Network segmentation is achieved through **Security Groups and NACLs**, not through separate subnets per service type. This approach:

- **Simplifies Management**: Fewer, larger subnets are easier to manage
- **Better IP Utilization**: /20 subnets (4096 addresses) provide ample IP space
- **Flexible Segmentation**: Security groups provide fine-grained access control
- **Cost Efficiency**: Fewer subnets reduce NAT Gateway requirements

### VPC Endpoints

VPC endpoints provide **private connectivity** to AWS services without internet access:

- **Interface Endpoints**: For services requiring private IP addresses (SSM, Secrets Manager, ECR, etc.)
- **Gateway Endpoints**: For S3 and DynamoDB (free, no additional cost)
- **Private Access**: All AWS service access stays within the VPC

### Management Server

An optional EC2 management server provides:

- **Secure Access**: Via AWS Systems Manager Session Manager (no SSH keys required)
- **Administrative Tasks**: Troubleshooting, kubectl access, Terraform operations
- **Tool Installation**: Pre-configured with kubectl, helm, terraform, gh, etc.
- **EKS Access**: Pre-configured IAM role for EKS cluster access

## Resources

### VPC and Networking

- **VPC**: Main VPC with DNS support enabled
- **Internet Gateway**: Provides internet access for NAT Gateways
- **NAT Gateways**: One per availability zone for high availability
- **Subnets**: 
  - 3 public subnets (for NAT Gateways)
  - 3 private subnets (for workloads)
  - 3 isolated subnets (for databases)
- **Route Tables**: Separate route tables for public, private, and isolated subnets

### VPC Endpoints

- **Interface Endpoints**: SSM, Secrets Manager, ECR, ECR API, CloudWatch Logs, etc.
- **Gateway Endpoints**: S3, DynamoDB
- **Security Groups**: Restricted egress to VPC CIDR for security

### KMS Keys

- **General Purpose Key**: For encrypting general resources
- **Secrets Manager Key**: For encrypting secrets in AWS Secrets Manager
- **Prometheus Key** (optional): For encrypting Prometheus workspace
- **Grafana Key** (optional): For encrypting Grafana workspace
- **CloudWatch Logs Key**: For encrypting CloudWatch log groups

### Secrets Manager

- **Secret Storage**: Secure storage for application secrets
- **KMS Encryption**: All secrets encrypted with dedicated KMS key
- **Automatic Rotation**: Support for automatic secret rotation

### Management Server (Optional)

- **EC2 Instance**: Amazon Linux 2023 with pre-installed tools
- **IAM Role**: SSM access and EKS cluster access
- **Security Group**: Restricted ingress/egress rules
- **IMDSv2**: Enforced for enhanced security
- **User Data**: Automated installation of kubectl, helm, terraform, gh, etc.

### CloudWatch Logs

- **Infrastructure Logs**: Centralized logging for infrastructure operations
- **Retention**: 365 days (compliance requirement, except sandbox)
- **KMS Encryption**: All logs encrypted at rest

## Security Principles

### Network Security

- **Private Subnets**: Workloads deployed in private subnets (no public IPs)
- **Isolated Subnets**: Databases in isolated subnets with no internet access
- **Security Groups**: Least privilege ingress/egress rules
- **NACLs**: Subnet-level firewall rules for defense in depth

### Encryption

- **KMS Keys**: Customer-managed keys for all encryption
- **Secrets Manager**: All secrets encrypted with dedicated KMS key
- **CloudWatch Logs**: All logs encrypted at rest
- **EBS Volumes**: Encrypted by default with KMS keys

### Access Control

- **VPC Endpoints**: Private access to AWS services (no internet required)
- **Security Groups**: Restricted egress to VPC CIDR where possible
- **IMDSv2**: Enforced on EC2 instances for enhanced metadata security
- **IAM Roles**: Least privilege access for all resources

### Instance Security

- **IMDSv2**: Enforced on management server to prevent SSRF attacks
- **EBS Optimization**: Enabled for better performance
- **Detailed Monitoring**: Enabled for production workloads
- **Security Groups**: Restricted to VPC CIDR for ingress

### Audit and Compliance

- **VPC Flow Logs**: Can be enabled for network traffic auditing
- **CloudWatch Logs**: All infrastructure operations logged
- **365-Day Retention**: Compliance requirement (except sandbox)

## Well-Architected Framework

### Operational Excellence

- **Automated Deployment**: Infrastructure defined as code
- **Monitoring**: CloudWatch logs for all operations
- **Documentation**: Clear network architecture and security design
- **Management Tools**: Pre-configured management server for operations

### Security

- **Network Isolation**: Private and isolated subnets for defense in depth
- **Encryption**: All data encrypted at rest and in transit
- **Access Control**: Least privilege IAM roles and security groups
- **VPC Endpoints**: Private access to AWS services
- **IMDSv2**: Enforced for enhanced EC2 security

### Reliability

- **Multi-AZ Deployment**: NAT Gateways and subnets across 3 availability zones
- **High Availability**: NAT Gateways provide redundancy for outbound access
- **Backup**: KMS keys and secrets can be backed up
- **Monitoring**: CloudWatch logs for troubleshooting

### Performance Efficiency

- **VPC Endpoints**: Private connectivity reduces latency
- **EBS Optimization**: Enabled for better disk performance
- **NAT Gateways**: Managed service for reliable outbound access
- **Subnet Sizing**: /20 subnets provide ample IP space

### Cost Optimization

- **Gateway Endpoints**: Free S3 and DynamoDB access via VPC endpoints
- **NAT Gateway Optimization**: Shared NAT Gateways across workloads
- **Lifecycle Management**: Optional management server (can be stopped when not in use)
- **Log Retention**: Configurable retention (shorter for sandbox)

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
vpc_cidr = "10.0.0.0/16"

# Management Server (optional)
enable_management_server = true
management_server_instance_type = "t3.medium"
management_server_public_access = false  # Use Session Manager instead

# VPC Endpoints
enable_ssm_endpoints = true
enable_secrets_manager_endpoint = true
```

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
3. Configure Remote-SSH for management server (if enabled):
   ```bash
   ./scripts/setup-remote-ssh.sh
   ```

## Outputs

- `vpc_id`: ID of the main VPC
- `vpc_cidr_block`: CIDR block of the VPC
- `public_subnet_ids`: List of public subnet IDs
- `private_subnet_ids`: List of private subnet IDs
- `isolated_subnet_ids`: List of isolated subnet IDs
- `nat_gateway_ids`: List of NAT Gateway IDs
- `vpc_endpoints_security_group_id`: Security group ID for VPC endpoints
- `kms_key_general_arn`: ARN of general purpose KMS key
- `kms_key_secrets_manager_arn`: ARN of Secrets Manager KMS key
- `management_server_instance_id`: Instance ID of management server (if enabled)
- `ssm_instance_role_arn`: ARN of SSM instance role

## References

- [AWS VPC Best Practices](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-security-best-practices.html)
- [VPC Endpoints](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints.html)
- [AWS Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [AWS Well-Architected Framework - Security](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/welcome.html)
- [IMDSv2 Best Practices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-instance-metadata-service.html)

