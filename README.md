# hello-aws

📋 Contains a basic but secure example on how to run Unique, fully automated on every release, on Amazon Web Services. ⛔️ Work in progress and experimental.

> [!WARNING]  
> This repository is a `hello world` (that is why its called `hello-aws`) example. Unique is not responsible and liable for any inaccuracies or misinterpretations. Users of this repository must make sure to validate the contents, test accordingly and validate the applied changes with their own governance, compliance and security processes/teams!

## Overview

This repository implements a layered AWS landing zone architecture following AWS Cloud Adoption Framework (CAF) and Well-Architected Framework (WAF) best practices. The infrastructure is organized into distinct layers, each with a specific purpose and clear dependencies.

## Architecture

The landing zone is organized into the following layers, deployed in order:

1. **01-bootstrap**: Foundational infrastructure for Terraform state management and CI/CD authentication
2. **02-governance**: Account-specific governance controls (budgets, Config rules, IAM policies)
3. **03-infrastructure**: Core networking infrastructure (VPC, subnets, VPC endpoints, KMS keys)
4. **04-data-and-ai**: Data storage and AI services (Aurora, ElastiCache, S3, Bedrock, Prometheus, Grafana)
5. **05-compute**: Containerized compute infrastructure (EKS, ECR)
6. **06-applications**: Application-specific resources

Each layer has its own Terraform state file stored in the shared S3 bucket created by the bootstrap layer.

## File Organization

All layers follow [HashiCorp's official best practices](https://developer.hashicorp.com/terraform/language/modules/develop) for Terraform file organization:

### Standard Structure

```
{layer-name}/
├── terraform/            # Terraform configuration files
│   ├── versions.tf          # Terraform and provider version constraints
│   ├── providers.tf         # Provider configuration
│   ├── backend.tf            # Terraform backend configuration
│   ├── variables.tf          # Input variables
│   ├── naming.tf             # Naming module for consistent resource naming
│   ├── locals.tf             # Local values and computed values
│   ├── data.tf               # Data sources
│   ├── {resource-type}.tf   # Resource-specific files (e.g., vpc.tf, eks.tf)
│   ├── outputs.tf            # Output values
│   ├── policies/            # External IAM policy JSON files (if needed)
│   └── environments/        # Environment-specific configurations
│       ├── dev/
│       │   ├── 00-config.auto.tfvars
│       │   └── backend-config.hcl
│       ├── test/
│       ├── prod/
│       └── sbx/
└── scripts/              # Deployment and utility scripts (if needed)
```

### File Organization Principles

- **Separation of concerns**: Terraform files in `terraform/`, scripts in `scripts/`
- **Organize by concern**: Files are named by resource type or purpose (e.g., `s3.tf`, `iam-roles.tf`)
- **Descriptive names**: No numeric prefixes - file names clearly indicate their purpose
- **Standard files**: `versions.tf`, `providers.tf`, `variables.tf`, `outputs.tf` follow Terraform conventions
- **No execution order dependency**: Terraform determines execution order from resource dependencies, not file order

## Prerequisites

Before deploying any layer, ensure you have:

1. **AWS Account**: Access to an AWS account with appropriate permissions
2. **AWS CLI**: Configured with credentials or IAM role (version 2.x recommended)
3. **Terraform**: Version >= 1.5.0
4. **Git**: For cloning the repository
5. **Session Manager Plugin**: For accessing EC2 instances via SSM (optional, for infrastructure layer)

## Common Configuration

Common configuration values are defined in `common.auto.tfvars` at the repository root. This file contains values shared across all layers:

- AWS region and account ID
- Organization identifiers (org, org_moniker)
- Client identifiers (client, client_name)
- Semantic version (set by CI/CD)

**Important**: This file must be created manually before deploying the bootstrap layer. Copy `common.auto.tfvars.template` to `common.auto.tfvars` and update the values for your organization and client.

## Deployment Workflow

### Step 1: Configure Common Values

Before deploying any layer, you must configure the common values file:

1. Copy the template file:
   ```bash
   cp common.auto.tfvars.template common.auto.tfvars
   ```

2. Edit `common.auto.tfvars` and update the following values:
   - `aws_region`: Your AWS region (e.g., `"eu-central-2"`)
   - `org`: Your organization name (e.g., `"unique"`)
   - `org_moniker`: Your organization short name (e.g., `"uq"`)
   - `client`: Your client/project name (e.g., `"dogfood"`)
   - `client_name`: Your client/project full name (e.g., `"Dog Food AG"`)
   - `semantic_version`: Version number (typically set by CI/CD, default: `"0.1.0"`)

### Step 2: Deploy Bootstrap Layer

The bootstrap layer creates the foundational infrastructure for Terraform state management. It must be deployed first using the automated bootstrap script:

```bash
cd 01-bootstrap/scripts
./bootstrap.sh <environment>
```

**Environments**: `dev`, `test`, `prod`, `sbx`

**Examples**:
```bash
./bootstrap.sh sbx
./bootstrap.sh dev --auto-approve
./bootstrap.sh prod --skip-plan
```

The bootstrap script will:
1. Initialize Terraform (using local backend initially)
2. Deploy the S3 bucket, KMS key, and access logging infrastructure
3. Automatically generate/update `backend-config.hcl` files for all layers
4. Migrate state to the S3 backend

**Note**: The bootstrap script automatically updates all layers' `backend-config.hcl` files with the correct S3 bucket name, KMS key alias, and region. You do not need to manually update these files.

### Step 3: Deploy Layers in Sequence

After the bootstrap layer is deployed, deploy the remaining layers in order:

1. **Governance Layer** (`02-governance`):
   ```bash
   ./scripts/deploy.sh governance <environment>
   ```

2. **Infrastructure Layer** (`03-infrastructure`):
   ```bash
   ./scripts/deploy.sh infrastructure <environment>
   ```

3. **Data and AI Layer** (`04-data-and-ai`):
   ```bash
   ./scripts/deploy.sh data-and-ai <environment>
   ```

4. **Compute Layer** (`05-compute`):
   ```bash
   ./scripts/deploy.sh compute <environment>
   ```

5. **Applications Layer** (`06-applications`):
   ```bash
   ./scripts/deploy.sh applications <environment>
   ```

**Deployment Script Options**:
- `--auto-approve`: Skip interactive confirmation
- `--skip-plan`: Skip the plan step and apply directly

**Examples**:
```bash
./scripts/deploy.sh governance sbx
./scripts/deploy.sh infrastructure dev --auto-approve
./scripts/deploy.sh compute prod --skip-plan --auto-approve
```

## State Management

All layers share a single S3 bucket and KMS key for state management (created by the bootstrap layer). Each layer stores its state file in a dedicated path:

- `bootstrap/terraform.tfstate`
- `governance/terraform.tfstate`
- `infrastructure/terraform.tfstate`
- `data-and-ai/terraform.tfstate`
- `compute/terraform.tfstate`
- `applications/terraform.tfstate`

**State Locking**: Terraform uses native S3 locking (`use_lockfile = true`) instead of DynamoDB. This provides:
- Simpler architecture (no DynamoDB table required)
- Automatic lock file management
- Lock files stored alongside state files in S3

This approach provides:
- Centralized state management
- Consistent security (encryption, versioning, native S3 locking)
- Cost efficiency (shared resources, no DynamoDB table)
- Organized structure (separate paths per layer)

## Layer Documentation

Each layer has comprehensive documentation covering design rationale, security principles, and Well-Architected Framework considerations:

- **[01-bootstrap](./01-bootstrap/README.md)**: State management and CI/CD authentication
  - Centralized state management architecture
  - Native S3 locking (no DynamoDB)
  - Automated backend configuration
  - Security and compliance considerations

- **[02-governance](./02-governance/README.md)**: Account-level governance controls
  - Cost management with AWS Budgets
  - Compliance monitoring with Config rules
  - IAM governance roles and policies
  - Operational excellence practices

- **[03-infrastructure](./03-infrastructure/README.md)**: Networking and foundational infrastructure
  - Three-tier subnet architecture (public, private, isolated)
  - VPC endpoints for private AWS service access
  - Management server with Session Manager
  - Network security and encryption

- **[04-data-and-ai](./04-data-and-ai/README.md)**: Data storage and AI services
  - Aurora PostgreSQL and ElastiCache Redis
  - S3 buckets with lifecycle policies
  - Amazon Bedrock for foundation models
  - Managed Prometheus and Grafana

- **[05-compute](./05-compute/README.md)**: Containerized compute (EKS, ECR)
  - Private EKS cluster with IRSA support
  - ECR repositories with image scanning
  - ECR pull through cache
  - Security and access control

- **[06-applications](./06-applications/README.md)**: Application deployment (GitOps)
  - ArgoCD for continuous deployment
  - Helmfile for chart management
  - Multi-environment support
  - Secrets management with External Secrets

## Best Practices

1. **Layer Dependencies**: Always deploy layers in the specified order
2. **State Management**: Never manually edit Terraform state files
3. **Backend Configuration**: Backend configs are automatically updated by the bootstrap script
4. **Common Variables**: Configure `common.auto.tfvars` before deploying bootstrap layer
5. **Environment Separation**: Use separate state files per environment
6. **Tagging**: All resources are automatically tagged via the naming module
7. **Encryption**: All state and resources are encrypted at rest using KMS
8. **Versioning**: State files are versioned in S3 for recovery
9. **Locking**: Native S3 locking prevents concurrent Terraform operations
10. **Least Privilege**: IAM policies follow least privilege principle
11. **Authentication**: AWS SSO (IAM Identity Center) is the only permitted authentication mechanism for human access

## Troubleshooting

### Common Issues

**State Lock Errors**: If Terraform is stuck with a lock, check the S3 bucket for lock files (`.terraform.tfstate.lock.info`). Lock files are automatically managed by Terraform and should be removed automatically when operations complete. If a lock persists, verify no other Terraform operations are running, then manually remove the lock file from S3 if necessary.

**Backend Migration**: The bootstrap script automatically handles state migration from local to S3 backend. For manual migration, use `terraform init -migrate-state -backend-config=environments/{env}/backend-config.hcl`.

**Missing Dependencies**: Ensure prerequisite layers are deployed before deploying dependent layers. The deployment order is: bootstrap → governance → infrastructure → data-and-ai → compute → applications.

**Configuration Errors**: 
- Verify `common.auto.tfvars` exists and is correctly configured before deploying bootstrap
- Verify environment-specific `00-config.auto.tfvars` files are correctly configured
- Ensure backend-config.hcl files are present (automatically generated by bootstrap script)

**Bootstrap Script Issues**: If the bootstrap script fails, ensure:
- AWS credentials are configured (use `aws sts get-caller-identity` to verify)
- You have permissions to create S3 buckets, KMS keys, and IAM resources
- The `common.auto.tfvars` file exists and is properly formatted

## Security

- **Authentication**: AWS SSO (IAM Identity Center) is the only permitted authentication mechanism for human access. Long-lived credentials (access keys) are not permitted for human users.
- **State Security**: All state files are encrypted at rest using KMS, versioned in S3, and protected by native S3 locking
- **Access Control**: IAM policies follow least privilege principle
- **Resource Encryption**: Resources are encrypted using customer-managed KMS keys
- **Network Security**: VPC endpoints provide private connectivity to AWS services
- **Network Segmentation**: Security groups and NACLs enforce network segmentation
- **IMDSv2**: EC2 instances enforce Instance Metadata Service Version 2 (IMDSv2) for enhanced security
- **EKS Security**: EKS clusters have public access disabled and use private endpoints

## Contributing

See [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md) for guidelines.

## License

See [LICENSE](./LICENSE) for details.

## References

- [AWS Cloud Adoption Framework](https://aws.amazon.com/cloud-adoption-framework/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [HashiCorp Terraform Best Practices](https://developer.hashicorp.com/terraform/language/modules/develop)
- [AWS Landing Zone Guide](https://docs.aws.amazon.com/prescriptive-guidance/latest/landing-zone-guide/welcome.html)
