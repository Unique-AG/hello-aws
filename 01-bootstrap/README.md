# 01-bootstrap Layer

## Overview

The bootstrap layer establishes the foundational infrastructure required for Terraform state management and CI/CD authentication. This layer must be deployed first before any other layers, as it creates the shared S3 bucket, KMS key, and IAM roles that all subsequent layers depend on.

## Design Rationale

### Centralized State Management

The bootstrap layer implements a **shared state management architecture** where all layers use a single S3 bucket and KMS key for storing Terraform state. This design provides:

- **Consistency**: All layers follow the same security and encryption standards
- **Cost Efficiency**: Shared resources reduce operational overhead
- **Simplicity**: Single point of configuration for state management
- **Organization**: State files are organized by layer path (e.g., `bootstrap/terraform.tfstate`, `infrastructure/terraform.tfstate`)

### Native S3 Locking

Instead of using DynamoDB for state locking, this implementation uses **native S3 locking** (`use_lockfile = true`). This approach:

- Eliminates the need for a DynamoDB table, reducing costs and complexity
- Provides automatic lock file management
- Stores lock files alongside state files in S3 for easier troubleshooting
- Maintains the same concurrency protection as DynamoDB-based locking

### Automated Backend Configuration

The bootstrap script automatically generates and updates `backend-config.hcl` files for all layers after deployment. This ensures:

- Consistency across all layers
- No manual configuration required
- Automatic propagation of bootstrap outputs (S3 bucket, KMS key, region)

### Two-Phase Deployment

The bootstrap layer uses a **two-phase deployment approach**:

1. **Local Backend Phase**: Initial deployment uses local backend to create the S3 bucket
2. **S3 Backend Migration**: After S3 bucket creation, state is automatically migrated to S3 backend

This approach solves the "chicken-and-egg" problem of needing an S3 bucket to store state for creating the S3 bucket.

## Resources

### S3 Buckets

- **Terraform State Bucket**: Stores state files for all layers
  - Versioning enabled for state recovery
  - KMS encryption at rest
  - Access logging to dedicated access logs bucket
  - Public access blocked
  - Lifecycle policies for old versions
  - Bucket policy enforcing HTTPS-only access

- **Access Logs Bucket**: Stores access logs for the state bucket
  - Versioning enabled
  - KMS encryption at rest
  - Public access blocked

### KMS Keys

- **Terraform State Key**: Customer-managed KMS key for encrypting state files
  - Automatic key rotation enabled
  - Policy allows S3 and CloudWatch Logs to use the key
  - Conditional GitHub Actions OIDC role access (if configured)
  - Minimum 7-day deletion window (enforced for compliance)

### IAM Roles

- **GitHub Actions OIDC Role** (optional): Enables CI/CD deployments via OIDC
  - Trust policy restricted to specific GitHub repository
  - Permissions limited to Terraform state bucket access
  - No long-lived credentials required

### CloudWatch Log Groups

- **Terraform Operations Logs**: Centralized logging for Terraform operations
  - Retention: 365 days (compliance requirement, except sandbox)
  - KMS encryption at rest
  - Organized by organization, client, and environment

## Security Principles

### Encryption at Rest

- All state files encrypted using customer-managed KMS keys
- KMS key rotation enabled automatically
- Access logs bucket encrypted with same KMS key
- CloudWatch logs encrypted with KMS

### Encryption in Transit

- Bucket policy enforces HTTPS-only access (`aws:SecureTransport`)
- All Terraform operations use HTTPS for S3 backend
- No unencrypted connections permitted

### Access Control

- Bucket policy restricts access to:
  - Current AWS account root
  - GitHub Actions OIDC role (if configured)
- No public access allowed
- IAM policies follow least privilege principle

### Audit and Compliance

- S3 access logging enabled for audit trail
- CloudWatch logs for Terraform operations
- Versioning enabled for state recovery
- Minimum 365-day log retention (except sandbox)

### Authentication

- **AWS SSO (IAM Identity Center) is the only permitted authentication mechanism for human access**
- Long-lived credentials (access keys) are not permitted for human users
- Service-to-service authentication uses IAM roles with temporary credentials
- GitHub Actions uses OIDC for authentication (no access keys)

## Well-Architected Framework

### Operational Excellence

- **Automated Deployment**: Bootstrap script automates the entire deployment process
- **State Management**: Centralized state with automatic backend configuration
- **Logging**: Comprehensive CloudWatch logging for all operations
- **Documentation**: Clear deployment instructions and automation scripts

### Security

- **Encryption**: All data encrypted at rest and in transit
- **Access Control**: Least privilege IAM policies
- **Audit Trail**: S3 access logging and CloudWatch logs
- **Compliance**: 365-day log retention for compliance requirements
- **No Public Access**: All resources are private by default

### Reliability

- **Versioning**: S3 versioning enables state recovery
- **Backup**: State files are versioned and can be recovered
- **Locking**: Native S3 locking prevents concurrent modifications
- **Lifecycle Management**: Automatic cleanup of old state versions

### Performance Efficiency

- **Shared Resources**: Single S3 bucket and KMS key for all layers
- **Cost Optimization**: No DynamoDB table required (native S3 locking)
- **Lifecycle Policies**: Automatic transition of old versions to cheaper storage

### Cost Optimization

- **Shared Infrastructure**: Single S3 bucket and KMS key reduce costs
- **Lifecycle Policies**: Automatic cleanup of old state versions
- **No DynamoDB**: Native S3 locking eliminates DynamoDB costs
- **Access Logs**: Separate bucket for cost tracking and analysis

## Deployment

### Prerequisites

1. Configure `common.auto.tfvars` at repository root
2. AWS credentials configured (via AWS SSO)
3. Appropriate IAM permissions to create S3 buckets, KMS keys, and IAM roles

### Deployment Steps

```bash
cd 01-bootstrap/scripts
./bootstrap.sh <environment>
```

**Environments**: `dev`, `test`, `prod`, `sbx`

**Options**:
- `--auto-approve`: Skip interactive confirmation
- `--skip-plan`: Skip the plan step and apply directly

### Post-Deployment

After successful deployment, the bootstrap script automatically:

1. Generates `backend-config.hcl` files for all layers
2. Migrates state from local to S3 backend
3. Displays outputs (S3 bucket name, KMS key alias, region)

You can now proceed to deploy other layers using the deployment scripts.

## Outputs

- `s3_bucket_name`: Name of the Terraform state bucket
- `s3_bucket_arn`: ARN of the Terraform state bucket
- `kms_key_id`: ID of the KMS key for state encryption
- `kms_key_arn`: ARN of the KMS key
- `kms_key_alias`: Alias of the KMS key (e.g., `alias/kms-...-tfstate`)
- `github_actions_role_arn`: ARN of GitHub Actions OIDC role (if configured)
- `cloudwatch_log_group_name`: Name of CloudWatch log group
- `aws_account_id`: Current AWS account ID
- `aws_region`: Current AWS region

## References

- [Terraform S3 Backend](https://www.terraform.io/docs/language/settings/backends/s3.html)
- [AWS KMS Best Practices](https://docs.aws.amazon.com/kms/latest/developerguide/best-practices.html)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [GitHub Actions OIDC with AWS](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)

