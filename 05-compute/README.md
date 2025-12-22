# 05-compute Layer

## Overview

The compute layer provides containerized compute infrastructure including Amazon EKS (Elastic Kubernetes Service) and Amazon ECR (Elastic Container Registry). This layer establishes the Kubernetes foundation for deploying containerized applications.

## Design Rationale

### EKS Architecture

The EKS cluster is designed for **security and reliability**:

- **Private Endpoints**: EKS API server accessible only from within the VPC
- **Public Access Disabled**: No public internet access to control plane
- **Private Subnets**: Worker nodes deployed in private subnets
- **KMS Encryption**: Cluster secrets encrypted with customer-managed KMS key
- **Control Plane Logging**: Comprehensive logging to CloudWatch

### ECR Architecture

ECR provides **secure container image storage**:

- **Pull Through Cache**: Reduces latency and costs for upstream registries
- **Image Scanning**: Automatic vulnerability scanning on push
- **KMS Encryption**: All images encrypted at rest
- **Lifecycle Policies**: Automatic cleanup of old images

### Access Control

EKS access is managed via **IAM Roles and Access Entries**:

- **Management Server Access**: Pre-configured IAM role for kubectl access
- **IRSA Support**: IAM Roles for Service Accounts for pod-level permissions
- **Access Entries**: Modern EKS access control (replaces aws-auth ConfigMap)
- **Authentication Mode**: API only (access entries, ConfigMap disabled)

### Node Group Configuration

EKS node groups are configured for **reliability and performance**:

- **Multi-AZ Deployment**: Nodes across all availability zones
- **Auto Scaling**: Configurable min/max/desired node counts
- **Instance Types**: Configurable per environment (larger for production)
- **Disk Size**: Configurable EBS volume size

## Resources

### EKS Cluster

- **Control Plane**: Managed Kubernetes control plane
  - Private endpoint only (no public access)
  - KMS encryption for secrets
  - Control plane logging to CloudWatch
  - OIDC provider for IRSA
  - Access entries for IAM-based authentication

- **Node Groups**: Managed worker nodes
  - Multi-AZ deployment
  - Auto scaling enabled
  - Security group restricted to VPC CIDR
  - IAM role for node operations

### ECR Repositories

- **Application Repositories**: For application container images
  - Image scanning on push
  - Immutable tags (production)
  - Lifecycle policies for cleanup
  - KMS encryption at rest

### ECR Pull Through Cache

- **Upstream Registries**: Docker Hub, ECR Public, Quay.io, GHCR, Azure Container Registry
  - Reduces latency for image pulls
  - Reduces costs (no egress charges)
  - Automatic caching

### IAM Roles

- **EKS Cluster Role**: For EKS control plane operations
- **EKS Node Role**: For worker node operations
- **IRSA OIDC Provider**: For IAM Roles for Service Accounts

### CloudWatch Logs

- **EKS Cluster Logs**: Control plane logs
  - Retention: Configurable (30 days default)
  - KMS encryption at rest
  - Log types: api, audit, authenticator, controllerManager, scheduler

## Security Principles

### Cluster Security

- **Private Endpoints**: EKS API server accessible only from VPC
- **Public Access Disabled**: No internet access to control plane
- **KMS Encryption**: Cluster secrets encrypted with customer-managed key
- **Security Groups**: Restricted ingress/egress to VPC CIDR

### Network Security

- **Private Subnets**: Worker nodes in private subnets (no public IPs)
- **Security Groups**: Node security group restricted to VPC CIDR
- **VPC Endpoints**: Private access to ECR and other AWS services

### Access Control

- **IAM-Based Authentication**: Access entries for fine-grained control
- **IRSA**: IAM Roles for Service Accounts for pod-level permissions
- **Least Privilege**: IAM policies follow least privilege principle
- **Management Server**: Pre-configured access for administrative tasks

### Image Security

- **Image Scanning**: Automatic vulnerability scanning on push
- **KMS Encryption**: All images encrypted at rest
- **Immutable Tags**: Production repositories use immutable tags
- **Lifecycle Policies**: Automatic cleanup of old/vulnerable images

### Audit and Compliance

- **Control Plane Logging**: All API operations logged to CloudWatch
- **Audit Logs**: Kubernetes audit logs for compliance
- **CloudWatch Retention**: Configurable retention for compliance

## Well-Architected Framework

### Operational Excellence

- **Managed Service**: EKS provides managed Kubernetes control plane
- **Automated Scaling**: Node groups auto-scale based on demand
- **Logging**: Comprehensive control plane logging
- **Documentation**: Clear cluster configuration and access procedures

### Security

- **Private Access**: EKS API server accessible only from VPC
- **Encryption**: All data encrypted at rest and in transit
- **Access Control**: IAM-based authentication and authorization
- **Image Security**: Vulnerability scanning and lifecycle management
- **Network Isolation**: Nodes in private subnets

### Reliability

- **Multi-AZ Deployment**: Nodes across all availability zones
- **Auto Scaling**: Automatic node scaling for capacity management
- **Managed Service**: AWS manages control plane availability
- **Backup**: etcd backups managed by AWS

### Performance Efficiency

- **ECR Pull Through Cache**: Reduces image pull latency and costs
- **Auto Scaling**: Right-size cluster based on workload
- **Instance Types**: Configurable per environment (optimize for workload)
- **VPC Endpoints**: Private connectivity reduces latency

### Cost Optimization

- **ECR Pull Through Cache**: Reduces egress charges for upstream registries
- **Auto Scaling**: Scale down during low usage periods
- **Lifecycle Policies**: Automatic cleanup of old images
- **Instance Types**: Right-size nodes for workload requirements

## Deployment

### Prerequisites

1. Infrastructure layer must be deployed first
2. `common.auto.tfvars` configured at repository root
3. Environment-specific configuration in `environments/{env}/00-config.auto.tfvars`

### Configuration

Key configuration options:

```hcl
# EKS Configuration
eks_cluster_version = "1.28"
eks_endpoint_private_access = true
eks_endpoint_public_access = false  # Disabled for security
eks_node_group_instance_types = ["m6i.large"]
eks_node_group_desired_size = 3
eks_node_group_min_size = 2
eks_node_group_max_size = 10

# ECR Configuration
ecr_repositories = [
  {
    name = "app-backend"
    image_tag_mutability = "IMMUTABLE"
    scan_on_push = true
  }
]

# Azure Container Registry (for pull through cache)
acr_registry_url = "uniqueapp.azurecr.io"
acr_username = ""  # Retrieved from 1Password
acr_password = ""  # Retrieved from 1Password
```

### Deployment Steps

```bash
./scripts/deploy.sh compute <environment>
```

**Environments**: `dev`, `test`, `prod`, `sbx`

**Options**:
- `--auto-approve`: Skip interactive confirmation
- `--skip-plan`: Skip the plan step and apply directly

### Post-Deployment

After deployment:

1. Configure kubectl access:
   ```bash
   ./05-compute/scripts/setup-kubectl.sh
   ```

2. Verify cluster access:
   ```bash
   kubectl get nodes
   kubectl get namespaces
   ```

3. Verify ECR repositories:
   ```bash
   aws ecr describe-repositories
   ```

4. Test ECR pull through cache (if configured):
   ```bash
   docker pull <upstream-registry>/<image>
   ```

## Outputs

- `eks_cluster_id`: EKS cluster ID
- `eks_cluster_arn`: EKS cluster ARN
- `eks_cluster_endpoint`: EKS API server endpoint
- `eks_cluster_version`: Kubernetes version
- `eks_node_group_arn`: EKS node group ARN
- `ecr_repository_urls`: List of ECR repository URLs
- `ecr_pull_through_cache_endpoint`: ECR pull through cache endpoint
- `eks_oidc_provider_arn`: OIDC provider ARN for IRSA

## Notes

### EKS Access Control

EKS access is managed exclusively via **access entries** (modern approach). The cluster is configured with `API` authentication mode, which disables the legacy `aws-auth` ConfigMap for enhanced security. All access must be configured via IAM-based access entries.

### IRSA (IAM Roles for Service Accounts)

IRSA allows Kubernetes pods to assume IAM roles for AWS service access. The OIDC provider is automatically created when the EKS cluster is created. Use IRSA for pod-level AWS permissions instead of access keys.

### ECR Pull Through Cache

ECR pull through cache reduces latency and costs for images from upstream registries (Docker Hub, GHCR, etc.). Images are cached in ECR, eliminating egress charges and reducing pull times.

### Azure Container Registry Integration

For pulling images from Azure Container Registry, configure ACR credentials via environment variables or AWS Secrets Manager. The EKS node group IAM role can be configured to access ACR credentials stored securely.

## References

- [Amazon EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [EKS Access Entries](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html)
- [IAM Roles for Service Accounts (IRSA)](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [ECR Pull Through Cache](https://docs.aws.amazon.com/AmazonECR/latest/userguide/pull-through-cache.html)
- [AWS Well-Architected Framework - Security](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/welcome.html)
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/pod-security-standards/)

