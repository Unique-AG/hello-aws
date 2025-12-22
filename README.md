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
├── README.md              # Layer-specific documentation
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
- Semantic version and deployment timestamp (set by CI/CD)

See [CONFIGURATION.md](./CONFIGURATION.md) for detailed configuration information.

## Deployment Workflow

### Step 1: Configure Common Values

Update `common.auto.tfvars` at the repository root with your organization and client information.

### Step 2: Deploy Layers in Order

Layers must be deployed in the specified order due to dependencies:

1. **Bootstrap Layer** (`01-bootstrap`): Deploy first to create state management infrastructure
2. **Governance Layer** (`02-governance`): Deploy after bootstrap
3. **Infrastructure Layer** (`03-infrastructure`): Deploy after bootstrap (depends on bootstrap)
4. **Data and AI Layer** (`04-data-and-ai`): Deploy after infrastructure (depends on infrastructure)
5. **Compute Layer** (`05-compute`): Deploy after infrastructure (depends on infrastructure)
6. **Applications Layer** (`06-applications`): Deploy last (depends on compute and data layers)

### Step 3: Update Backend Configuration

After deploying the bootstrap layer, update each layer's `terraform/environments/{env}/backend-config.hcl` with the bootstrap outputs:

- S3 bucket name
- DynamoDB table name
- KMS key alias

### Step 4: Deploy Each Layer

For each layer, follow the deployment steps in its README:

```bash
cd {layer-name}/terraform
terraform init -backend-config=environments/{env}/backend-config.hcl
terraform plan -var-file=../../common.auto.tfvars -var-file=environments/{env}/00-config.auto.tfvars
terraform apply -var-file=../../common.auto.tfvars -var-file=environments/{env}/00-config.auto.tfvars
```

**Note**: The bootstrap layer includes an automated deployment script that simplifies the initial setup.

## State Management

All layers share a single S3 bucket, DynamoDB table, and KMS key for state management (created by the bootstrap layer). Each layer stores its state file in a dedicated path:

- `bootstrap/terraform.tfstate`
- `governance/terraform.tfstate`
- `infrastructure/terraform.tfstate`
- `data-and-ai/terraform.tfstate`
- `compute/terraform.tfstate`
- `applications/terraform.tfstate`

This approach provides:
- Centralized state management
- Consistent security (encryption, versioning, locking)
- Cost efficiency (shared resources)
- Organized structure (separate paths per layer)

## Layer Documentation

Each layer has detailed documentation in its own README:

- [01-bootstrap](./01-bootstrap/README.md): State management and CI/CD authentication
- [02-governance](./02-governance/README.md): Account-specific governance controls
- [03-infrastructure](./03-infrastructure/README.md): Networking and foundational infrastructure
- [04-data-and-ai](./04-data-and-ai/README.md): Data storage and AI services
- [05-compute](./05-compute/README.md): Containerized compute (EKS, ECR)
- [06-applications](./06-applications/README.md): Application-specific resources

## Best Practices

1. **Layer Dependencies**: Always deploy layers in the specified order
2. **State Management**: Never manually edit Terraform state files
3. **Backend Configuration**: Update backend configs after bootstrap deployment
4. **Common Variables**: Use `common.auto.tfvars` for shared values
5. **Environment Separation**: Use separate state files per environment
6. **Tagging**: All resources are automatically tagged via the naming module
7. **Encryption**: All state and resources are encrypted at rest using KMS
8. **Versioning**: State files are versioned in S3 for recovery
9. **Locking**: DynamoDB prevents concurrent Terraform operations
10. **Least Privilege**: IAM policies follow least privilege principle

## Troubleshooting

### Common Issues

**State Lock Errors**: If Terraform is stuck with a lock, check the DynamoDB table for stale locks (they expire after 1 hour).

**Backend Migration**: When migrating from local to S3 backend, use `terraform init -migrate-state`.

**Missing Dependencies**: Ensure prerequisite layers are deployed before deploying dependent layers.

**Configuration Errors**: Verify `common.auto.tfvars` and environment-specific `00-config.auto.tfvars` are correctly configured.

For layer-specific troubleshooting, see the individual layer READMEs.

## Security

- All state files are encrypted at rest using KMS
- All state files are versioned in S3
- State locking prevents concurrent modifications
- IAM policies follow least privilege principle
- Resources are encrypted using customer-managed KMS keys
- VPC endpoints provide private connectivity to AWS services
- Network segmentation via security groups and NACLs

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
