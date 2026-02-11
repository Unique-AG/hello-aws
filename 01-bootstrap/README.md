# 01-bootstrap Layer

The bootstrap layer creates the S3 bucket, KMS key, CloudWatch log group, and optional GitHub Actions OIDC role that all subsequent layers depend on. It must be deployed first.

## Resources

- **S3 state bucket**: Versioning, KMS encryption, access logging, HTTPS-only bucket policy, lifecycle rules for old versions
<<<<<<< HEAD
- **S3 access logs bucket**: Versioning, KMS encryption, public access blocked, lifecycle policy (90-day expiration, 30-day noncurrent version expiration)
- **KMS key**: Customer-managed, automatic rotation, policy grants for S3, CloudWatch Logs, and GitHub Actions (if OIDC configured)
- **CloudWatch log group**: KMS encrypted, minimum 365-day retention for non-sandbox environments
- **GitHub Actions OIDC provider + IAM role** (optional): Federated authentication scoped to a specific GitHub repository

## Bootstrap Script

The bootstrap script (`scripts/bootstrap.sh`) solves the chicken-and-egg problem: Terraform needs an S3 bucket to store state, but the S3 bucket is created by Terraform. The script handles this in phases:

### Phase 1: Deploy with Local Backend

1. Validates AWS credentials via `aws sts get-caller-identity`
2. Reads `org_moniker`, `product_moniker`, and `aws_region` from `common.auto.tfvars`
3. Temporarily moves `backend.tf` aside to disable the S3 backend
4. Runs `terraform init` with local backend
5. Runs `terraform plan` and `terraform apply` to create the S3 bucket, KMS key, and other resources

### Phase 2: Generate Backend Configuration

After deployment, the script reads Terraform outputs (`s3_bucket_name`, `kms_key_alias`, `aws_region`) and generates `backend-config.hcl` files from the template (`backend-config.hcl.template`) for every layer it finds:

```
01-bootstrap/terraform/environments/{env}/backend-config.hcl
02-governance/terraform/environments/{env}/backend-config.hcl
03-infrastructure/terraform/environments/{env}/backend-config.hcl
...
```

Each generated file contains the shared S3 bucket, KMS key, and a layer-specific state key:

```hcl
bucket        = "s3-{org}-{product}-{env_short}-{region}-tfstate"
key           = "bootstrap/terraform.tfstate"    # varies per layer
region        = "eu-central-2"
encrypt       = true
kms_key_id    = "alias/kms-{org}-{product}-{env}-{region}-tfstate"
use_lockfile  = true
```

The script discovers layers by scanning for `*/terraform/backend-config.hcl.template` files. State keys are mapped from layer directory names (e.g., `03-infrastructure` maps to `infrastructure/terraform.tfstate`).

### Phase 3: Migrate State to S3

1. Restores `backend.tf`
2. Runs `terraform init -migrate-state` with the generated `backend-config.hcl`
3. State is now in S3 — subsequent runs use the S3 backend directly

### Usage

```bash
cd 01-bootstrap/scripts
./bootstrap.sh <environment>
```

**Environments**: `prod`, `stag`, `dev`, `sbx`

**Options**:
- `--auto-approve`: Skip interactive confirmation
- `--skip-plan`: Skip the plan step and apply directly
- `--connect-only`: Connect to existing remote state without deploying (generates `backend-config.hcl` from expected resource names without running plan/apply)

### Re-running

On subsequent runs, the script detects that state already exists in S3 (by attempting `terraform init` + `terraform state list` against the S3 backend) and skips the local backend phase entirely.

## Outputs

| Output | Description | Conditional |
|---|---|---|
| `s3_bucket_name` | Name of the Terraform state bucket | |
| `s3_bucket_arn` | ARN of the Terraform state bucket | |
| `kms_key_id` | ID of the KMS key for state encryption | `enable_server_side_encryption` |
| `kms_key_arn` | ARN of the KMS key | `enable_server_side_encryption` |
| `kms_key_alias` | Alias of the KMS key | `enable_server_side_encryption` |
| `github_actions_role_arn` | ARN of GitHub Actions OIDC role | `use_oidc` + `github_repository` |
| `cloudwatch_log_group_name` | Name of CloudWatch log group | |
| `aws_account_id` | Current AWS account ID | |
| `aws_region` | Current AWS region | |

## Design Decisions

**Shared state bucket**: All layers share one S3 bucket with per-layer key paths (`bootstrap/terraform.tfstate`, `infrastructure/terraform.tfstate`, etc.). This reduces operational overhead vs per-layer buckets.

**Native S3 locking**: Uses `use_lockfile = true` instead of DynamoDB, eliminating a resource and its associated cost.

**Bucket policy**: Grants access to the deploying user/role (`aws_caller_identity.current.arn`) and the GitHub Actions OIDC role (if configured). All other access is denied.

**KMS deletion window**: Defaults to 30 days. Setting `kms_deletion_window = 0` enforces the AWS minimum of 7 days (immediate deletion is not possible).
