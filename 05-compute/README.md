# 05-compute Layer

## Overview

The compute layer provides containerized compute infrastructure: Amazon EKS with Pod Identity-based workload IAM and Amazon ECR with pull-through caching (Docker Hub, ECR Public, Quay, GHCR, ACR). This layer supports three network distribution models (see [root README](../README.md#network-access-model)):

- **Internal** (default): Private-only access via corporate network (VPN / Direct Connect / Transit Gateway)
- **CloudFront**: Public internet access via CloudFront edge network — enable via `kong_nlb_dns_name`, `internal_alb_certificate_domain`, `enable_cloudfront_vpc_origin`
- **Dual**: Both corporate network and public internet access (Transit Gateway configured in infrastructure layer)

ACR credentials use Terraform's `secret_string_wo` write-only attribute and `ephemeral` variables so they never appear in state or plan files.

## Design Rationale

### EKS Architecture

The EKS cluster is configured for **private-only API access** with IAM-based authentication:

- **Authentication Mode**: `API` only — access entries replace the legacy `aws-auth` ConfigMap
- **Access Entries**: Management server (cluster admin) + SandboxAdministrator (sbx only)
- **KMS Encryption**: Cluster secrets encrypted with the customer-managed general KMS key from infrastructure layer
- **Control Plane Logging**: All 5 log types (`api`, `audit`, `authenticator`, `controllerManager`, `scheduler`) to CloudWatch
- **Private Endpoints**: API server accessible only from within the VPC; public access disabled
- **Security Groups**: Cluster SG allows 443 from VPC endpoints SG, nodes SG, and management server SG; egress restricted to VPC CIDR

### Node Groups

Two node groups share the same IAM role and scaling configuration:

- **Standard** (`node-group`): General workloads
- **Large** (`node-group-large`): System workloads (Kong, etc.)
- Both deploy across all private subnets (multi-AZ), support configurable instance types, capacity type (ON_DEMAND/SPOT), disk size, labels, and taints
- Node IAM role includes `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly`, plus an inline policy for `ecr:BatchImportUpstreamImage` and `ecr:CreateRepository` (pull-through cache)

### EKS Addons

Five managed addons, all deployed after the node group is ready:

| Addon | Purpose |
|---|---|
| `eks-pod-identity-agent` | Required for Pod Identity associations |
| `aws-ebs-csi-driver` | PersistentVolumeClaim provisioning (gp3); Pod Identity via standalone association |
| `coredns` | Cluster DNS |
| `kube-proxy` | Network proxy |
| `vpc-cni` | VPC-native pod networking |

> **Note**: The EBS CSI addon uses `lifecycle { ignore_changes = [service_account_role_arn] }` because cross-account assumed roles cannot call `UpdateAddon` with role changes (PassRole restriction). The Pod Identity association is managed separately.

### Pod Identity Roles

Eight IAM roles use the `pods.eks.amazonaws.com` service principal with `sts:AssumeRole` + `sts:TagSession` (EKS Pod Identity pattern, not legacy IRSA):

| Role | Namespace | Service Account | AWS Permissions |
|---|---|---|---|
| EBS CSI Driver | `kube-system` | `ebs-csi-controller-sa` | `AmazonEBSCSIDriverPolicy` (managed) |
| Cluster Secrets | `external-secrets` | `external-secrets` | Secrets Manager `GetSecretValue`/`DescribeSecret` + KMS `Decrypt` |
| Cert-Manager Route 53 | `cert-manager` | `cert-manager` | Route 53 `ChangeResourceRecordSets`, `GetChange`, `ListHostedZones` |
| Assistants Core | `unique` | `assistants-core` | Bedrock `InvokeModel`/`InvokeModelWithResponseStream` + S3 CRUD on `*-ai-data` + Secrets Manager `GetSecretValue` |
| LiteLLM | `unique` | `litellm` | Bedrock `InvokeModel`/`InvokeModelWithResponseStream` |
| Ingestion | `unique` | `backend-service-ingestion` | S3 CRUD on `*-ai-data` |
| Ingestion Worker | `unique` | `backend-service-ingestion-worker` | Bedrock `InvokeModel`/`InvokeModelWithResponseStream` + S3 CRUD on `*-ai-data` |
| Speech | `unique` | `backend-service-speech` | Transcribe `StartStreamTranscription`, `StartTranscriptionJob`, etc. |

Bedrock roles grant access to foundation models (`arn:aws:bedrock:*::foundation-model/*`), EU cross-region inference profiles (`arn:aws:bedrock:*::inference-profile/eu.*`), and account-scoped inference profiles.

### ECR

ECR provides **secure container image storage** with automated vulnerability scanning:

- **Repositories**: Per-application, KMS-encrypted, configurable tag mutability and lifecycle policies
- **Enhanced Scanning**: Registry-level, continuous scanning for all repositories (configurable via `ecr_scanning_rules`)
- **EventBridge**: Captures ECR image scan findings with CRITICAL or HIGH severity (rule created, SNS target commented out for future use)

### ECR Pull-Through Cache

Pull-through cache reduces external registry dependencies and egress costs:

- **Upstream Registries**: Docker Hub, ECR Public, Quay.io, GHCR, Azure Container Registry (ACR)
- **ACR Credentials**: Stored in Secrets Manager using `secret_string_wo` (write-only — never in Terraform state). The `acr_username` and `acr_password` variables are also declared `ephemeral = true`, so they are never persisted in plan files. A resource policy grants the ECR service-linked role access to the secret
- **ACR Alias**: Automatically extracted from `acr_registry_url` (e.g., `uniqueapp` from `uniqueapp.azurecr.io`), registered as both the full URL and the short alias
- **Conditional**: ACR-related cache rules are skipped entirely if `acr_registry_url` is empty

### CloudFront VPC Origin (Optional)

Exposes the internal ALB to CloudFront without public internet exposure. Disabled by default — enable by setting `kong_nlb_dns_name`, `kong_nlb_security_group_id`, and `internal_alb_certificate_domain`:

- **Architecture**: CloudFront -> VPC Origin -> Internal ALB (TLS) -> Kong NLB (HTTP:80) -> Kong Gateway
- **Internal ALB**: Application load balancer in private subnets with CloudFront managed prefix list SG
- **TLS Termination**: ACM certificate (DNS validation) on the ALB; TLS 1.3 security policy (`ELBSecurityPolicy-TLS13-1-2-2021-06`)
- **Target Registration**: Kong NLB DNS resolved to IPs via `dns_a_record_set`, registered as IP targets on port 80
- **RAM Sharing**: VPC Origin shared with the connectivity account (via `connectivity_account_id` variable) using AWS RAM in `us-east-1` (CloudFront resources are global)
- **Two-Phase Deployment**: First deploy with `enable_cloudfront_vpc_origin = false` (creates ALB), then set to `true` (creates VPC Origin)

### WebSocket ALB (Optional)

Created alongside the CloudFront ALB when `kong_nlb_dns_name` is set. CloudFront VPC Origins do not support WebSocket connections, so a separate **public** ALB handles WebSocket traffic:

- **Architecture**: CloudFront -> Standard Custom Origin -> Public ALB -> Kong NLB -> Kong -> Chat Backend
- **Security**: Ingress restricted to CloudFront managed prefix list (no open `0.0.0.0/0`)
- **Subnets**: Public subnets (internet-facing)
- **HTTP Redirect**: Port 80 redirects to HTTPS (301)
- **Shared Certificate**: Reuses the same ACM certificate as the internal ALB

### VPC Endpoint

- **EKS Interface Endpoint**: `com.amazonaws.{region}.eks` — enables `kubectl` and EKS API calls from private subnets without internet access. Uses the shared VPC endpoints security group from infrastructure layer.

## Resources

### EKS Cluster

- **Cluster**: Private endpoint, KMS-encrypted secrets, API-only auth mode, 5 control plane log types
- **Access Entries**: Management server (cluster admin) + SandboxAdministrator (sbx-only, cluster admin)
- **Security Groups**: Cluster SG (443 from VPC endpoints, nodes, management server) + Nodes SG (all TCP from VPC CIDR, self, cluster)
- **CloudWatch Log Group**: `/aws/eks/eks-{naming-id}/cluster`, KMS-encrypted, configurable retention

### EKS Node Groups

- **Standard**: `{naming-id}-node-group` — general workloads
- **Large**: `{naming-id}-node-group-large` — system workloads (Kong, etc.)
- **IAM Role**: Shared role with 3 managed policies + 1 inline (ECR pull-through cache)

### EKS Addons

- `eks-pod-identity-agent`, `aws-ebs-csi-driver`, `coredns`, `kube-proxy`, `vpc-cni`
- All use `resolve_conflicts_on_update = "OVERWRITE"`, depend on node group

### ECR

- **Repositories**: KMS-encrypted, scan-on-push, configurable lifecycle policies
- **Registry Scanning**: Enhanced or Basic, continuous scanning on all repositories
- **EventBridge Rule**: Captures CRITICAL/HIGH scan findings

### ECR Pull-Through Cache

- **Cache Rules**: Docker Hub, ECR Public, Quay.io, GHCR, ACR (conditional)
- **ACR Secret**: Secrets Manager with `secret_string_wo`, KMS-encrypted, resource policy for ECR service-linked role

### ALBs (Optional — requires `kong_nlb_dns_name`)

- **CloudFront ALB**: Internal, private subnets, CloudFront prefix list SG, HTTPS (443) + HTTP (80) listeners
- **WebSocket ALB**: Public, public subnets, CloudFront prefix list SG, HTTPS (443) + HTTP->HTTPS redirect (80)
- **Target Groups**: IP-type, port 80 (HTTP), Kong NLB IPs resolved via DNS

### CloudFront VPC Origin (Optional — requires `enable_cloudfront_vpc_origin`)

- **VPC Origin**: HTTPS-only, TLS 1.2, attached to internal ALB
- **RAM Share**: `us-east-1` provider, shared with connectivity account (via `connectivity_account_id` variable)

### VPC Endpoint

- **EKS**: Interface endpoint, private subnets, private DNS enabled

## Security Principles

### Encryption

- **At Rest**: EKS secrets, ECR images, CloudWatch logs — all use customer-managed KMS keys from infrastructure layer
- **In Transit**: TLS 1.3 on ALB listeners, HTTPS-only VPC Origin, TLS for EKS API

### Network Isolation

- **EKS**: Private endpoint only, no public API access
- **Nodes**: Private subnets, security group restricted to VPC CIDR
- **ALBs**: CloudFront managed prefix list (no `0.0.0.0/0`), even on the public WebSocket ALB
- **VPC Endpoint**: Private access to EKS API without internet

### Access Control

- **EKS Auth**: API-only mode, access entries (no `aws-auth` ConfigMap)
- **Pod Identity**: 8 roles with least-privilege policies, `pods.eks.amazonaws.com` service principal
- **Cross-Account**: RAM sharing uses `connectivity_account_id` variable (no hardcoded account IDs); cross-account IAM role managed in infrastructure layer
- **ACR Credentials**: Write-only (`secret_string_wo`) + ephemeral variables — never in Terraform state or plan files

### Audit and Compliance

- **Terraform Version**: Pinned to `>= 1.10.0` (native S3 locking)
- **AWS Provider**: Pinned to `~> 5.100`
- **Control Plane Logging**: All 5 EKS log types enabled
- **CloudWatch Retention**: Configurable per environment (default 30 days, sbx: 7 days)

### Suppressed Security Findings and Production Guardrails

All scanner findings are either fixed or explicitly suppressed with rationale. Inline `#checkov:skip` and `.trivyignore` entries reference the central security baseline document. Sandbox relaxations and SCP enforcement recommendations are also documented there.

See **[docs/security-baseline.md](../docs/security-baseline.md)** for the complete suppression inventory, sbx relaxation matrix, and SCP implementation guide.

## Deployment

### Prerequisites

1. Infrastructure layer deployed (provides VPC, KMS keys, subnets, VPC endpoints, management server)
2. `common.auto.tfvars` configured at repository root
3. Environment-specific configuration in `environments/{env}/00-config.auto.tfvars`

### Configuration

Key configuration options (defaults shown, override per environment):

```hcl
# EKS
eks_cluster_version            = "1.28"
eks_node_group_instance_types  = ["m6i.large"]
eks_node_group_desired_size    = 2       # min: 1, max: 4
eks_node_group_disk_size       = 50
eks_endpoint_private_access    = true
eks_endpoint_public_access     = false

# ECR
ecr_enhanced_scanning_enabled  = true

# ACR (pull-through cache)
acr_registry_url = "uniquecr.azurecr.io"   # "" to disable

# VPC Endpoint
enable_eks_endpoint            = true
```

#### Optional: CloudFront VPC Origin

Enable external access via CloudFront. Requires Kong NLB to be deployed first (two-phase):

```hcl
kong_nlb_dns_name               = null    # Set to Kong NLB DNS after deployment
kong_nlb_security_group_id      = null    # Set to EKS node SG
internal_alb_certificate_domain = null    # e.g., "*.sbx.rbcn.ai"
connectivity_account_id         = null    # Set to connectivity account ID for RAM sharing
enable_cloudfront_vpc_origin    = false   # Set true after ALB exists
```

### Deployment Steps

**With ACR credentials** (retrieves credentials from 1Password):

```bash
.scripts/deploy-with-acr.sh compute <environment> [1password-item] [deploy-args...]
```

**Without ACR** (standard deploy):

```bash
./scripts/deploy.sh compute <environment>
```

**Environments**: `dev`, `test`, `prod`, `sbx`

**Options**:
- `--auto-approve`: Skip interactive confirmation
- `--skip-plan`: Skip the plan step and apply directly

### Post-Deployment

1. Configure kubectl access:
   ```bash
   ./05-compute/scripts/setup-kubectl.sh
   ```

2. Verify cluster access:
   ```bash
   kubectl get nodes
   kubectl get namespaces
   ```

3. Enable CloudFront VPC Origin (after Kong NLB is deployed):
   - Set `kong_nlb_dns_name`, `kong_nlb_security_group_id`, `internal_alb_certificate_domain`
   - Re-apply, then set `enable_cloudfront_vpc_origin = true` and apply again

## Outputs

### EKS Cluster
- `eks_cluster_id`, `eks_cluster_arn`, `eks_cluster_name`, `eks_cluster_endpoint`, `eks_cluster_version`
- `eks_cluster_security_group_id`, `eks_node_security_group_id`
- `eks_node_group_id`, `eks_node_group_arn`
- `eks_cluster_name_for_alb_discovery` (for connectivity layer ALB tag-based discovery)

### ECR
- `ecr_repository_urls`, `ecr_repository_arns` (maps by repo name)
- `ecr_registry_url` (base ECR registry URL)
- `ecr_pull_through_cache_registry_urls`, `ecr_pull_through_cache_rule_ids`
- `ecr_scanning_configuration_scan_type`, `ecr_image_scan_event_rule_arn`

### ACR
- `acr_secret_arn`, `acr_pull_through_cache_url`

### Pod Identity Roles
- `pod_identity_ebs_csi_role_arn`
- `pod_identity_cluster_secrets_role_arn`
- `pod_identity_assistants_core_role_arn`
- `pod_identity_cert_manager_route53_role_arn`
- `pod_identity_litellm_role_arn`
- `pod_identity_ingestion_role_arn`
- `pod_identity_ingestion_worker_role_arn`
- `pod_identity_speech_role_arn`

### CloudFront VPC Origin
- `cloudfront_vpc_origin_id`, `cloudfront_vpc_origin_arn`
- `internal_alb_dns_name`, `internal_alb_certificate_arn`, `internal_alb_certificate_validation_records`
- `cloudfront_alb_arn`, `cloudfront_alb_dns_name`, `cloudfront_alb_security_group_id`

### WebSocket ALB
- `websocket_alb_dns_name`

### VPC Endpoint
- `eks_endpoint_id`

### General
- `aws_region`, `aws_account_id`

## References

- [Amazon EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [EKS Access Entries](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html)
- [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
- [ECR Pull Through Cache](https://docs.aws.amazon.com/AmazonECR/latest/userguide/pull-through-cache.html)
- [CloudFront VPC Origins](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-vpc-origins.html)
- [AWS RAM Sharing](https://docs.aws.amazon.com/ram/latest/userguide/what-is.html)
- [Terraform Write-Only Attributes](https://developer.hashicorp.com/terraform/language/values/variables#ephemeral-variables)
