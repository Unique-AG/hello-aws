# hello-aws

Contains a basic but secure example on how to run Unique, fully automated on every release, on Amazon Web Services. Work in progress and experimental.

> [!WARNING]
> This repository is a `hello world` (that is why its called `hello-aws`) example. Unique is not responsible and liable for any inaccuracies or misinterpretations. Users of this repository must make sure to validate the contents, test accordingly and validate the applied changes with their own governance, compliance and security processes/teams!

## Overview

This repository implements a layered AWS landing zone architecture following AWS Cloud Adoption Framework (CAF) and Well-Architected Framework (WAF) best practices. The infrastructure is organized into distinct layers, each with a specific purpose and clear dependencies.

## Architecture

### Platform Topologies

hello-aws supports three platform topologies, depending on how your AWS organization is structured:

| Topology | Description | Route 53 | Transit Gateway | Elastic Container Registry | Best for |
|---|---|---|---|---|---|
| **Standalone** | Single account, all services co-located | Workload account | N/A | Workload account | PoCs, small deployments |
| **Hub-and-spoke** | Central connectivity account with spoke workload accounts | Connectivity account | Connectivity account | Workload account | Multi-account organizations |
| **Hub-and-spoke with shared services** | Hub-and-spoke plus a dedicated shared services account | Connectivity account | Connectivity account | Shared services account | Enterprise deployments |

The topology determines where cross-cutting services (Route 53 hosted zones, Transit Gateway, ECR pull-through caches, VPC peering) are provisioned. Each layer's Terraform configuration accepts variables to target the correct account for these resources.

#### Configuring by Topology

The following table shows which layer variables change per topology:

| Variable | Standalone | Hub-and-spoke | Hub-and-spoke with shared services |
|---|---|---|---|
| `route53_account_id` | Workload account | Connectivity account | Connectivity account |
| `route53_zone_id` | Created in 03-infrastructure | Pre-existing in connectivity account | Pre-existing in connectivity account |
| `transit_gateway_id` | N/A (single VPC) | Pre-existing in connectivity account | Pre-existing in connectivity account |
| `ecr_account_id` | Workload account | Workload account | Shared services account |
| `connectivity_account_id` | N/A | Connectivity account | Connectivity account |

Set these values in each environment's `00-config.auto.tfvars` file. The layers affected are primarily **03-infrastructure** (networking, Route 53, Transit Gateway attachments) and **05-compute** (ECR pull-through cache, cross-account image access).

> [!NOTE]
> This repository currently implements the **hub-and-spoke** topology as the default example. Standalone and shared services variations require adjusting the account references in each layer's environment configuration.

> [!IMPORTANT]
> Cross-account access and authorizations (IAM roles, resource policies, RAM shares) are prerequisites for the hub-and-spoke and shared services topologies. The exact configuration depends on your organization's AWS account structure and is out of scope of this document.

### Layers

The landing zone is organized into layers that group resources by blast radius, change frequency, and statefulness. Resources that change together are co-located in the same layer, and stateful resources (databases, storage) are separated from stateless ones (compute, networking rules) to minimize risk during updates.

1. **01-bootstrap**: Foundational infrastructure for Terraform state management and CI/CD authentication
2. **02-governance**: Account-specific governance controls (budgets, Config rules, IAM policies)
3. **03-infrastructure**: Core networking infrastructure (VPC, subnets, VPC endpoints, KMS keys)
4. **04-data-and-ai**: Data storage and AI services (Aurora, ElastiCache, S3, Bedrock, Prometheus, Grafana)
5. **05-compute**: Containerized compute infrastructure (EKS, Elastic Container Registry)
6. **06-applications**: Application-specific resources

Layers are deployed in order. Lower layers (bootstrap, governance) change infrequently and have broad blast radius, while upper layers (compute, applications) change often with narrower impact. Each layer has its own Terraform state file stored in the shared S3 bucket created by the bootstrap layer.

### Availability Zones

Availability Zones (AZs) are defined once in the **03-infrastructure** layer and propagated to downstream layers via remote state. The infrastructure layer fetches available AZs using `data "aws_availability_zones"` and slices them to `availability_zone_count` (configurable per environment, default 2 for sandbox, 3 for production). This drives the creation of subnets (public, private, isolated), NAT gateways, and runner subnets.

The selected AZs are exported as an output and consumed by downstream layers (data-and-ai, compute) through remote state, ensuring that databases, EKS node groups, and other AZ-aware resources are deployed into the same zones as the VPC subnets. This single-source-of-truth approach prevents AZ mismatches across layers.

**Cost impact**: Each additional AZ multiplies AZ-bound resources — NAT gateways, subnets, EIPs, Aurora replicas, ElastiCache nodes, and EKS worker nodes. A multi-AZ production deployment provides high availability but increases networking and data-tier costs proportionally. Use `availability_zone_count = 1` for cost-sensitive development environments and `3` for production workloads requiring multi-AZ redundancy.

### Network Access Model

The standard layout deploys all resources as **internal-facing only** — no public endpoints, no public subnets with internet-facing load balancers, and no direct internet ingress. This is the recommended production configuration.

During initial deployment, Terraform accesses AWS services (S3 state bucket, KMS, IAM) via the public AWS API using SSO credentials. This is standard and secure — no VPC resources are exposed. Once the infrastructure layer provisions S3 Gateway Endpoints, the state bucket can be restricted to VPC-only access, and all subsequent operations run through internal endpoints.

The recommended deployment progression:

1. Deploy **01-bootstrap** and **02-governance** from a local machine or AWS CloudShell using SSO credentials — state is accessed via the AWS public API at this stage
2. Deploy **03-infrastructure**, which provisions VPC endpoints (including S3 Gateway Endpoint), a management server with SSM Session Manager, and GitHub Actions self-hosted runners — all within private subnets
3. From this point forward, all operations are performed through SSM Session Manager or the CI/CD runners. The S3 state bucket can be locked down to VPC-only access, and all remaining layers are deployed entirely internally

For ephemeral, short-lived evaluation deployments, each layer exposes configuration variables to optionally enable public access (e.g., public EKS API endpoint, public ALB). This is not recommended for production.

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

### Naming Module

The `modules/naming/` module provides structured naming conventions and tagging across all environments and layers. Each layer references it via `naming.tf` to generate consistent, length-constrained resource names (S3 buckets, IAM roles, EKS clusters, etc.) and a standard set of tags. This module can be replaced with your organization's own naming module or conventions.

All deployed resources are tagged with the `semantic_version` of the IaC configuration (`governance:SemanticVersion` tag). This provides traceability from any AWS resource back to the exact version of the infrastructure code that created or last modified it. The version should be injected by CI/CD from the git tag (e.g., `-var="semantic_version=$(git describe --tags --abbrev=0)"`) rather than maintained manually in `common.auto.tfvars`, which only contains a placeholder default.

### File Organization Principles

- **Separation of concerns**: Terraform files in `terraform/`, scripts in `scripts/`
- **Organize by concern**: Files are named by resource type or purpose (e.g., `s3.tf`, `iam-roles.tf`)
- **Descriptive names**: No numeric prefixes - file names clearly indicate their purpose
- **Standard files**: `versions.tf`, `providers.tf`, `variables.tf`, `outputs.tf` follow Terraform conventions
- **No execution order dependency**: Terraform determines execution order from resource dependencies, not file order
- **Convention over configuration**: Consistent file names, directory structures, and naming patterns reduce the need for per-layer documentation and make the codebase navigable by convention alone

## Prerequisites

Before deploying any layer, ensure you have:

1. **AWS Account**: Access to an AWS account with appropriate permissions
2. **AWS CLI**: Configured with credentials or IAM role (version 2.x recommended)
3. **Terraform**: Version >= 1.5.0
4. **Git**: For cloning the repository
5. **Session Manager Plugin**: For accessing EC2 instances via SSM (optional, for infrastructure layer)
6. **Unique AI ACR Credentials**: Access to the Unique container registry (Azure ACR) for pulling application images. Contact [Unique AI](https://unique.ch) to obtain your registry credentials.

> [!NOTE]
> **AWS Authentication**: The deployment scripts use AWS CLI credentials (`aws sts get-caller-identity`). For production environments, it is strongly recommended to use [AWS IAM Identity Center (SSO)](https://docs.aws.amazon.com/singlesignon/latest/userguide/what-is.html) instead of long-lived access keys. Configure SSO with `aws configure sso` and use named profiles.

## Common Configuration

Common configuration values are defined in `common.auto.tfvars` at the repository root. This file contains values shared across all layers:

- AWS region and account ID
- Organization identifiers (org, org_moniker)
- Product identifiers (product, product_name)
- Semantic version (set by CI/CD)

These values are critical because the naming module uses them to generate globally unique resource names. AWS resources such as S3 buckets, IAM roles, and KMS aliases must be unique within an account or globally across AWS. The naming module combines `org_moniker`, `product`, `environment`, and region into deterministic prefixes:

```
s3-df-unique-sbx-euc2-state          # S3 bucket (globally unique)
iam-df-unique-sbx-euc2-deploy        # IAM role (account-unique)
kms-df-unique-sbx-euc2-state         # KMS alias (account-unique)
eks-df-unique-sbx-euc2               # EKS cluster name
```

For ephemeral environments (e.g., PR previews, feature branches, load tests), use distinct `org_moniker` or `product` values to avoid name collisions with long-lived environments. For example, a short-lived PR environment could use `org_moniker = "df"` with `product = "unique-pr42"`, producing resource names like `s3-df-unique-pr42-sbx-euc2-state` that are isolated from the main deployment and can be torn down without risk.

**Important**: This file must be created manually before deploying the bootstrap layer. Copy `common.auto.tfvars.template` to `common.auto.tfvars` and update the values for your organization and product.

## Deployment Workflow

> [!NOTE]
> All scripts in this repository are provided for convenience only. The recommended approach is to release and deploy using CI/CD pipelines (e.g., GitHub Actions). The scripts are useful for initial bootstrapping, local development, and troubleshooting.

### Step 1: Configure Common Values

Before deploying any layer, you must configure the common values file:

1. Copy the template file:
   ```bash
   cp common.auto.tfvars.template common.auto.tfvars
   ```

2. Edit `common.auto.tfvars` and update the following values:
   - `aws_region`: Your AWS region (e.g., `"eu-central-2"`)
   - `org`: Your organization name (e.g., `"dogfood"`)
   - `org_moniker`: Your organization short name (e.g., `"df"`)
   - `product`: Your product/project name (e.g., `"unique"`)
   - `product_name`: Your product/project full name (e.g., `"Unique AI"`)
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
./bootstrap.sh sbx --auto-approve
./bootstrap.sh sbx --skip-plan
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
   ./scripts/deploy.sh governance sbx
   ```

2. **Infrastructure Layer** (`03-infrastructure`):
   ```bash
   ./scripts/deploy.sh infrastructure sbx
   ```

3. **Data and AI Layer** (`04-data-and-ai`):
   ```bash
   ./scripts/deploy.sh data-and-ai sbx
   ```

4. **Compute Layer** (`05-compute`):
   ```bash
   ./scripts/deploy.sh compute sbx
   ```

5. **Applications Layer** (`06-applications`):
   ```bash
   ./scripts/deploy.sh applications sbx
   ```

**Deployment Script Options**:
- `--auto-approve`: Skip interactive confirmation
- `--skip-plan`: Skip the plan step and apply directly

**Examples**:
```bash
./scripts/deploy.sh governance sbx
./scripts/deploy.sh infrastructure sbx --auto-approve
./scripts/deploy.sh compute sbx --skip-plan --auto-approve
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

**Cross-Layer State**: Layers resolve dependencies by convention over configuration — each layer discovers prior layers' state using predictable S3 key paths derived from the layer name (e.g., `infrastructure/terraform.tfstate`), the shared backend bucket, and [Terraform remote state](https://developer.hashicorp.com/terraform/language/state/remote-state-data) data sources. This eliminates manual wiring between layers: the compute layer automatically finds the infrastructure layer's VPC and subnet IDs without explicit endpoint or ARN configuration. This can be reconfigured to match your organization's standardized patterns (e.g., SSM Parameter Store, Terraform Cloud workspaces, or static variable files).

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

**Missing Dependencies**: Ensure prerequisite layers are deployed before deploying dependent layers. The deployment order is: bootstrap -> governance -> infrastructure -> data-and-ai -> compute -> applications.

**Configuration Errors**:
- Verify `common.auto.tfvars` exists and is correctly configured before deploying bootstrap
- Verify environment-specific `00-config.auto.tfvars` files are correctly configured
- Ensure backend-config.hcl files are present (automatically generated by bootstrap script)

**Bootstrap Script Issues**: If the bootstrap script fails, ensure:
- AWS credentials are configured (use `aws sts get-caller-identity` to verify)
- You have permissions to create S3 buckets, KMS keys, and IAM resources
- The `common.auto.tfvars` file exists and is properly formatted

## Container Registry (ACR)

The compute layer (05-compute) configures an ECR pull-through cache that mirrors container images from Unique AI's Azure Container Registry (ACR). This allows your EKS cluster to pull application images without direct internet access to the ACR.

To deploy the compute layer, you need ACR credentials:
1. Contact [Unique AI](https://unique.ch) to obtain your ACR registry URL, username, and password
2. Set the credentials as environment variables before running `deploy.sh`:
   ```bash
   export TF_VAR_acr_registry_url="<your-registry>.azurecr.io"
   export TF_VAR_acr_username="<your-username>"
   export TF_VAR_acr_password="<your-password>"
   ./scripts/deploy.sh compute sbx
   ```

## Security

> [!IMPORTANT]
> The deployment scripts validate AWS credentials using `aws sts get-caller-identity`. While this works with access keys, it is strongly recommended to use **AWS IAM Identity Center (SSO)** for all human access. Long-lived access keys should be avoided in favor of short-lived SSO session credentials.

- **Authentication**: AWS SSO (IAM Identity Center) is the recommended authentication mechanism for human access. Long-lived credentials (access keys) are not permitted for human users in production.
- **State Security**: All state files are encrypted at rest using KMS, versioned in S3, and protected by native S3 locking
- **Access Control**: IAM policies follow least privilege principle
- **Resource Encryption**: Resources are encrypted using customer-managed KMS keys
- **Network Security**: VPC endpoints provide private connectivity to AWS services
- **Network Segmentation**: Security groups and NACLs enforce network segmentation
- **IMDSv2**: EC2 instances enforce Instance Metadata Service Version 2 (IMDSv2) for enhanced security
- **EKS Security**: EKS clusters have public access disabled and use private endpoints
- **Secrets Management**: No secrets are stored in Terraform configuration or state. All secrets are ephemeral — injected at deploy time via environment variables or retrieved from external secret managers. We recommend [1Password](https://1password.com), [Doppler](https://www.doppler.com), or [SOPS](https://github.com/getsops/sops) for secrets handling. At runtime, applications retrieve secrets from AWS Secrets Manager via [External Secrets Operator](https://external-secrets.io).
- **Secret Scanning**: Pre-commit hooks and CI checks powered by [gitleaks](https://github.com/gitleaks/gitleaks) prevent accidental credential leaks

### Validation and Security Scanning

The `scripts/validate.sh` script runs a multi-stage validation pipeline against any layer. Each tool in the stack serves a distinct purpose with no overlap:

| Tool | Category | Scope | Purpose |
|---|---|---|---|
| **`terraform fmt`** | Formatting | Terraform HCL | Enforces canonical code style — tabs, alignment, spacing |
| **`terraform validate`** | Syntax | Terraform HCL | Checks configuration syntax, type constraints, and internal consistency (requires `init`) |
| **[tflint](https://github.com/terraform-linters/tflint)** | Linting | Terraform HCL | Catches errors that `validate` misses — deprecated attributes, invalid instance types, naming conventions, provider-specific best practices |
| **[shellcheck](https://github.com/koalaman/shellcheck)** | Linting | Shell scripts | Static analysis for bash/sh — quoting bugs, subshell pitfalls, POSIX compliance |
| **[trivy](https://github.com/aquasecurity/trivy)** | Security | Terraform HCL | IaC misconfiguration scanning — unencrypted resources, overly permissive IAM, public exposure. Successor to [tfsec](https://github.com/aquasecurity/tfsec) (deprecated) |
| **[checkov](https://github.com/bridgecrewio/checkov)** | Compliance | Terraform HCL | Policy-as-code against compliance frameworks — CIS benchmarks, SOC2, HIPAA, PCI-DSS. Maps findings to specific control IDs |
| **[gitleaks](https://github.com/gitleaks/gitleaks)** | Secrets | Git history + staged files | Detects leaked credentials, API keys, and tokens before they are committed (pre-commit hook + CI) |

**Why trivy and checkov?** Trivy focuses on security misconfigurations (is this resource exposed? encrypted? properly scoped?). Checkov maps findings to compliance frameworks (does this meet CIS 1.2.3? SOC2 CC6.1?). Trivy tells you what's insecure; checkov tells you what's non-compliant. Secrets scanning is handled exclusively by gitleaks to avoid overlap.

```bash
# Full validation (requires backend access)
./scripts/validate.sh infrastructure sbx

# Lint-only mode (no backend access needed)
./scripts/validate.sh infrastructure sbx true
```

These tools are not prescriptive — use whichever subset fits your security posture. However, we strongly recommend integrating them as **deterministic gates through the change lifecycle** (commit, push, merge) — particularly when using agent-based SDLC workflows (e.g., AI coding agents, automated PR generation). Automated gates ensure that all infrastructure changes meet compliance and security standards regardless of origin.

### Secret Scanning

This repository includes a [gitleaks](https://github.com/gitleaks/gitleaks) configuration (`scripts/gitleaks-config.toml`) and a scanning script (`scripts/scan-secrets.sh`) to detect secrets before they are committed.

```bash
# Scan entire repository history
./scripts/scan-secrets.sh

# Scan only staged changes (used by pre-commit hook)
./scripts/scan-secrets.sh --staged

# Scan a specific commit
./scripts/scan-secrets.sh --commit --commit-hash abc123
```

**Installation**: `brew install gitleaks`

The scan runs automatically as a pre-commit hook when Git hooks are configured. To set up the hooks, copy or symlink from `scripts/hooks/`:
```bash
cp scripts/hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

## Contributing

See [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md) for guidelines.

## License

See [LICENSE](./LICENSE) for details.

## References

### Unique AI Documentation

- [AWS Overview](https://unique-ch.atlassian.net/wiki/spaces/PUBDOC/pages/1858961472/AWS)
  - [Phase 1: Prerequisites for Customer Managed Tenant for AWS](https://unique-ch.atlassian.net/wiki/spaces/PUBDOC/pages/1859780934)
  - [Phase 2: Setup and Implementation Guide for AWS](https://unique-ch.atlassian.net/wiki/spaces/PUBDOC/pages/1859190840)
  - [Phase 3: Run on AWS](https://unique-ch.atlassian.net/wiki/spaces/PUBDOC/pages/1860501536)

### AWS and Terraform

- [AWS Cloud Adoption Framework](https://aws.amazon.com/cloud-adoption-framework/)
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [HashiCorp Terraform Best Practices](https://developer.hashicorp.com/terraform/language/modules/develop)
- [AWS Landing Zone Guide](https://docs.aws.amazon.com/prescriptive-guidance/latest/landing-zone-guide/welcome.html)
