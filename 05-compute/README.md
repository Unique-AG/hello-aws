# 05-compute Layer

## Overview

The compute layer provides containerized compute infrastructure: Amazon EKS with Pod Identity-based workload IAM and Amazon ECR with pull-through caching (Docker Hub, ECR Public, Quay, GHCR, ACR). This layer supports three network distribution models (see [root README](../README.md#network-access-model)):

- **Internal** (default): Private-only access via corporate network (VPN / Direct Connect / Transit Gateway)
- **CloudFront**: Public internet access via CloudFront edge network — NLB, ALBs, and VPC Origin are managed in the infrastructure layer (`enable_ingress_nlb`, `enable_cloudfront_vpc_origin`)
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
- **Security Groups**: Cluster SG allows 443 from VPC endpoints SG, nodes SG, and management server SG; egress restricted to VPC CIDR. If ingress NLB exists, the EKS managed cluster SG also allows inbound from NLB SG for health checks.

### Node Groups

Node groups are defined via the `eks_node_groups` variable (a map of pool configurations). All pools share the same IAM role and deploy across all private subnets (multi-AZ):

- Each pool supports configurable instance types, capacity type (ON_DEMAND/SPOT), disk size, scaling limits, labels, and taints
- Pool names become the node group suffix: `{naming-id}-{pool-name}`
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

Nine IAM roles use the `pods.eks.amazonaws.com` service principal with `sts:AssumeRole` + `sts:TagSession` (EKS Pod Identity pattern, not legacy IRSA):

| Role | Namespace | Service Account | AWS Permissions |
|---|---|---|---|
| EBS CSI Driver | `kube-system` | `ebs-csi-controller-sa` | `AmazonEBSCSIDriverPolicy` (managed) + KMS encrypt/decrypt for EBS encryption |
| Cluster Secrets | `unique` | `external-secrets` | Secrets Manager `GetSecretValue`/`DescribeSecret` + KMS `Decrypt` |
| Cert-Manager Route 53 | `unique` | `cert-manager` | Route 53 `ChangeResourceRecordSets`, `GetChange`, `ListHostedZones` |
| Assistants Core | `unique` | `assistants-core` | Bedrock `InvokeModel`/`InvokeModelWithResponseStream` + S3 CRUD on `*-ai-data` + Secrets Manager `GetSecretValue` |
| LiteLLM | `unique` | `litellm` | Bedrock `InvokeModel`/`InvokeModelWithResponseStream` |
| Ingestion | `unique` | `backend-service-ingestion` | S3 CRUD on `*-ai-data` |
| Ingestion Worker | `unique` | `backend-service-ingestion-worker` | Bedrock `InvokeModel`/`InvokeModelWithResponseStream` + S3 CRUD on `*-ai-data` |
| Speech | `unique` | `backend-service-speech` | Transcribe `StartStreamTranscription`, `StartTranscriptionJob`, etc. |
| AWS LB Controller | `unique` | `aws-load-balancer-controller` | EC2, ELBv2, IAM, Cognito, ACM, WAFv2, Shield (manages TargetGroupBindings) |

Bedrock roles grant access to foundation models (`arn:aws:bedrock:*::foundation-model/*`), cross-region inference profiles (`eu.*` and `global.*`), and account-scoped inference profiles (both `inference-profile/*` and `application-inference-profile/*`).

### ECR

ECR provides **secure container image storage** with automated vulnerability scanning:

- **Repositories**: Per-application, KMS-encrypted, configurable tag mutability and lifecycle policies
- **Enhanced Scanning**: Registry-level, continuous scanning for all repositories (configurable via `ecr_scanning_rules`)
- **EventBridge**: Captures ECR image scan findings with CRITICAL or HIGH severity (rule created, SNS target commented out for future use)

### ECR Pull-Through Cache

Pull-through cache reduces external registry dependencies and egress costs. For authenticated registries (Docker Hub, GHCR), creating pull-through cache rules with credentials is the recommended approach — it avoids rate limits and provides reliable, cached access to upstream images.

- **Supported Upstream Registries**: Docker Hub, ECR Public, Quay.io, GCR, GHCR, Azure Container Registry (ACR). Enabled registries are configured via `ecr_pull_through_cache_upstream_registries`.
- **ACR Credentials**: Stored in Secrets Manager using `secret_string_wo` (write-only — never in Terraform state). The `acr_username` and `acr_password` variables are also declared `ephemeral = true`, so they are never persisted in plan files. A resource policy grants the ECR service-linked role access to the secret.
- **ACR Alias**: Automatically extracted from `acr_registry_url` (e.g., `myregistry` from `myregistry.azurecr.io`), registered as both the full URL and the short alias
- **Conditional**: ACR-related cache rules are skipped entirely if `acr_registry_url` is empty

### Ingress NLB, ALBs, and CloudFront VPC Origin (Infrastructure Layer)

The ingress NLB, ALBs, and CloudFront VPC Origin are **managed in the infrastructure layer** (`03-infrastructure`), not in this layer. This separation keeps pure networking resources independent of EKS:

- **Ingress NLB**: Terraform-managed internal NLB with IP-type target groups. The AWS Load Balancer Controller (deployed in the applications layer) registers ingress controller pod IPs via `TargetGroupBinding` CRDs — no manual target registration or `kong_nlb_dns_name` variable needed.
- **CloudFront ALB**: Internal ALB for CloudFront VPC Origin, forwards to NLB
- **WebSocket ALB**: Public ALB for WebSocket traffic (CloudFront VPC Origins don't support WebSocket)
- **VPC Origin**: Shared with connectivity account via AWS RAM

Architecture: `CloudFront -> ALB -> Ingress NLB -> Ingress Controller pods (via TargetGroupBinding)`

This compute layer provides only the **AWS Load Balancer Controller IAM role** (Pod Identity), since it requires the EKS cluster name. See the infrastructure layer README for NLB/ALB/VPC Origin configuration.

### VPC Endpoint

- **EKS Interface Endpoint**: `com.amazonaws.{region}.eks` — enables `kubectl` and EKS API calls from private subnets without internet access. Uses the shared VPC endpoints security group from infrastructure layer.

## Resources

### EKS Cluster

- **Cluster**: Private endpoint, KMS-encrypted secrets, API-only auth mode, 5 control plane log types
- **Access Entries**: Management server (cluster admin) + SandboxAdministrator (sbx-only, cluster admin)
- **Security Groups**: Cluster SG (443 from VPC endpoints, nodes, management server; NLB if present) + Nodes SG (all TCP from VPC CIDR, self, cluster)
- **CloudWatch Log Group**: `/aws/eks/eks-{naming-id}/cluster`, KMS-encrypted, configurable retention

### EKS Node Groups

- Configurable pool map via `eks_node_groups` — each pool creates `{naming-id}-{pool-name}`
- **IAM Role**: Shared role with 3 managed policies + 1 inline (ECR pull-through cache)

### EKS Addons

- `eks-pod-identity-agent`, `aws-ebs-csi-driver`, `coredns`, `kube-proxy`, `vpc-cni`
- All use `resolve_conflicts_on_update = "OVERWRITE"`, depend on node group

### ECR

- **Repositories**: KMS-encrypted, scan-on-push, configurable lifecycle policies
- **Registry Scanning**: Enhanced or Basic, continuous scanning on all repositories
- **EventBridge Rule**: Captures CRITICAL/HIGH scan findings

### ECR Pull-Through Cache

- **Cache Rules**: Configurable via `ecr_pull_through_cache_upstream_registries`; ACR rules are conditional on `acr_registry_url`
- **ACR Secret**: Secrets Manager with `secret_string_wo`, KMS-encrypted, resource policy for ECR service-linked role

### VPC Endpoint

- **EKS**: Interface endpoint, private subnets, private DNS enabled

## Security Principles

### Encryption

- **At Rest**: EKS secrets, ECR images, CloudWatch logs — all use customer-managed KMS keys from infrastructure layer
- **In Transit**: TLS for EKS API

### Network Isolation

- **EKS**: Private endpoint only, no public API access
- **Nodes**: Private subnets, security group restricted to VPC CIDR
- **VPC Endpoint**: Private access to EKS API without internet

### Access Control

- **EKS Auth**: API-only mode, access entries (no `aws-auth` ConfigMap)
- **Pod Identity**: 9 roles with least-privilege policies, `pods.eks.amazonaws.com` service principal
- **ACR Credentials**: Write-only (`secret_string_wo`) + ephemeral variables — never in Terraform state or plan files

### Audit and Compliance

- **Terraform Version**: Pinned to `>= 1.10.0` (native S3 locking)
- **AWS Provider**: Pinned to `~> 5.100`
- **Control Plane Logging**: All 5 EKS log types enabled
- **CloudWatch Retention**: Configurable per environment (default 7 days)

### Suppressed Security Findings and Production Guardrails

All scanner findings are either fixed or explicitly suppressed with rationale. Inline `#checkov:skip` and `.trivyignore` entries reference the central security baseline document. Sandbox relaxations and SCP enforcement recommendations are also documented there.

See **[docs/security-baseline.md](../docs/security-baseline.md)** for the complete suppression inventory, sbx relaxation matrix, and SCP implementation guide.

## Deployment

### Prerequisites

1. Infrastructure layer deployed (provides VPC, KMS keys, subnets, VPC endpoints, management server, ingress NLB, ALBs, VPC Origin)
2. `common.auto.tfvars` configured at repository root
3. Environment-specific configuration in `environments/{env}/00-config.auto.tfvars`

### Configuration

Key configuration options (defaults shown, override per environment):

```hcl
# EKS
eks_cluster_version           = "1.28"       # override per env
eks_endpoint_private_access   = true
eks_endpoint_public_access    = false

# Node pools (map of pool configs — override per env)
eks_node_groups = {
  steady = {
    instance_types = ["m6i.large"]
    desired_size   = 2
    min_size       = 0
    max_size       = 3
    labels         = { lifecycle = "persistent", scalability = "steady" }
    taints         = []
  }
}

# ECR
ecr_enhanced_scanning_enabled = true

# ACR (pull-through cache — "" to disable)
acr_registry_url = "example.azurecr.io"

# VPC Endpoint
enable_eks_endpoint           = true
```

> **Note**: Ingress NLB, ALBs, and CloudFront VPC Origin are configured in the infrastructure layer (`enable_ingress_nlb`, `enable_cloudfront_vpc_origin`).

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

3. Deploy applications layer (AWS Load Balancer Controller + ingress controller with TargetGroupBindings):
   ```bash
   # AWS LB Controller registers ingress controller pod IPs into Terraform-managed target groups
   kubectl get targetgroupbindings -n unique
   ```

## Outputs

### EKS Cluster
- `eks_cluster_id`, `eks_cluster_arn`, `eks_cluster_name`, `eks_cluster_endpoint`, `eks_cluster_version`
- `eks_cluster_security_group_id`, `eks_node_security_group_id`
- `eks_node_group_ids`, `eks_node_group_arns` (maps keyed by pool name)

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
- `pod_identity_aws_lb_controller_role_arn`

### VPC Endpoint
- `eks_endpoint_id`

### General
- `aws_region`, `aws_account_id`

## References

- [Amazon EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [EKS Access Entries](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html)
- [EKS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html)
- [ECR Pull Through Cache](https://docs.aws.amazon.com/AmazonECR/latest/userguide/pull-through-cache.html)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [TargetGroupBinding](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/targetgroupbinding/targetgroupbinding/)
- [Terraform Write-Only Attributes](https://developer.hashicorp.com/terraform/language/values/variables#ephemeral-variables)
