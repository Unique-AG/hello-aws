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
- **Security Groups**: Cluster SG allows 443 from VPC endpoints SG, nodes SG, and management server SG; egress restricted to VPC CIDR. Nodes SG uses standalone `aws_vpc_security_group_*_rule` resources (self, VPC CIDR ingress; HTTPS egress to VPC), attached to nodes via launch template. If ingress NLB exists, the EKS managed cluster SG also allows inbound from NLB SG for health checks.

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

Ten IAM roles use the `pods.eks.amazonaws.com` service principal with `sts:AssumeRole` + `sts:TagSession` (EKS Pod Identity pattern, not legacy IRSA):

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
| Peer Pods | `sbx` | `cloud-api-adaptor`, `peerpodctrl-controller-manager` | EC2 `RunInstances` on a `PeerPod`-tagged instance, `TerminateInstances` on the same tag, `CreateTags` on create only, plus the Describes the adaptor calls. Also grant and decrypt on the general KMS key — the pod VM AMI is encrypted, so EC2 creates a grant on the caller's behalf at launch |

Bedrock roles grant access to foundation models (`arn:aws:bedrock:*::foundation-model/*`), cross-region inference profiles (`eu.*` and `global.*`), and account-scoped inference profiles (both `inference-profile/*` and `application-inference-profile/*`).

### Conduct Pod VM Image

Conduct sandboxes run as Kata peer pods: `cloud-api-adaptor` launches one EC2 instance per sandbox from a **pod VM AMI**, an image built by the Confidential Containers project rather than derived from the EKS worker AMI. It is not created by Terraform — the AMI ID is supplied as the `<PODVM_AMI_ID>` placeholder in `instance-config.yaml`, and `validate-instance.sh` fails until it is set.

Two ways to obtain one:

**Copy the upstream image (sbx only).** The project publishes a pod VM AMI per release in `us-east-2`. `./05-compute/scripts/copy-podvm-ami.sh <env>` copies it into this deployment's region, re-encrypted under the general KMS key, and tags both the image and its snapshot with where they came from.

What it checks before copying:

- Architecture, boot mode and TPM support on every source image — a mismatch means the wrong image, not a cosmetic difference.
- Name and owner **only for the pinned AMI**, which is the CAA version the `peerpods` chart vendors. Bumping the chart means re-pinning it. With `--source-ami` those two are unknown, so it warns instead and tags the result accordingly rather than claiming upstream provenance.
- That the caller's account matches the environment's, and that both layers' state is for the same environment — each is init'd separately, so they can disagree and silently mix one environment's region with another's key. Without readable state it cannot check either, so it requires `--region` and `--kms-key-arn` explicitly rather than guessing.

`--verify-only` runs the source checks alone, and needs no state and no environment.

Understand what that image is before relying on it:

- Upstream describes it as a **debug** image published for proofs of concept. That is a
  build variant, not a label: the project's `make image-debug` target adds debugging
  packages and **enables serial console access into the pod VM**, which is at odds with
  the VM's purpose here.
- It is published by an AWS account that appears nowhere in the project's repository or CI, and which has published exactly one public AMI. There is no cryptographic link between that account and the project.
- Its backing snapshot is unencrypted upstream; the copy re-encrypts it, which addresses encryption but not provenance.

This is acceptable for `sbx`, where the value is verifying that the peer-pods path works end to end. It is **not** an acceptable basis for the sandbox boundary anywhere the sandbox runs real untrusted work.

**Build it from source (the intended path).** Two scripts, split so the image source and the AWS half are independent:

```bash
# On a Linux host with Docker — mkosi needs a privileged container
./05-compute/scripts/build-podvm-image.sh --check    # confirm the host first
./05-compute/scripts/build-podvm-image.sh            # produces podvm-<ref>-x86_64.raw

# From anywhere with credentials for this account
terraform -chdir=05-compute/terraform apply -var enable_podvm_image_import=true
./05-compute/scripts/import-podvm-ami.sh --image ./podvm-build/podvm-v0.22.0-x86_64.raw
terraform -chdir=05-compute/terraform apply -var enable_podvm_image_import=false
```

The build clones the CAA version pinned in the script — it must match the `peerpods` chart's appVersion — runs upstream's `make` unmodified, and writes a `.provenance` file recording the ref, commit, mkosi version and SHA256. The import refuses to proceed if the image no longer matches that record, and tags the AMI `Provenance=built-from-source` only when that check actually ran.

The build also sets `VERIFY_PROVENANCE=yes`, which upstream leaves off. The Makefile then runs `gh attestation verify` against the kata-agent and guest-component binaries as it pulls them, asserting each was built on its own repository from the expected commit — so the binaries baked into the image are attested even though the published pod VM artifact is not. It needs `gh` on the host; `--no-verify-provenance` opts out.

`TEE_PLATFORM` is deliberately left at its default of `none`. That builds filesystem-attester support only, which is what `DISABLECVM: "true"` in the overlay asks for; `TEE_PLATFORM=snp` is for confidential pod VMs on SEV-SNP instance types. The build otherwise needs no unusual hardware — upstream runs it on a stock `ubuntu-24.04` runner.

**Import staging is off by default.** `enable_podvm_image_import` creates the bucket and role VM Import/Export needs, and nothing else uses them, so they should not stand between imports. The role is scoped to the staging bucket, the general KMS key, and the snapshot/image calls that cannot be resource-scoped because they create the resource they name. Contrast upstream's `raw-to-ami.sh`, which creates an account-wide `vmimport` role with `Resource: "*"` on `ec2:RegisterImage`, `CopySnapshot` and `ModifySnapshotAttribute`, an unencrypted bucket, and cleans up neither.

The registered AMI is UEFI with `TpmSupport=v2.0`, IMDSv2-only, and encrypted under the general KMS key; the import verifies all four afterwards, because a pod VM missing UEFI or the TPM boots and then fails to attest.

**Assurance on the result.** `trivy vm ami:<id>` scans the registered image for vulnerabilities and secrets, and the import runs it automatically (`--skip-scan` to opt out). This only works on an image we own — trivy cannot read public snapshots, so the upstream AMI cannot be scanned in place at all. Note `trivy vm` is EXPERIMENTAL, supports only VMDK for local files (so scan the AMI, not the disk file), and cannot read LVM layouts.

**Importing upstream's non-debug artifact instead.** The project publishes the plain pod VM as an OCI artifact — `quay.io/confidential-containers/podvm-generic-ubuntu-amd64`, with the debug variant under a separate `-debug-` name. `import-podvm-ami.sh` accepts the qcow2 directly and converts it. It avoids the serial console but not the provenance question: the build workflow runs `actions/attest` with `push-to-registry`, yet neither the registry's referrers nor GitHub's attestation API holds an attestation for the released digest.

### ECR

ECR provides **secure container image storage** with automated vulnerability scanning:

- **Repositories**: Per-application, KMS-encrypted, configurable tag mutability and lifecycle policies
- **Enhanced Scanning**: Registry-level, continuous scanning for all repositories (configurable via `ecr_scanning_rules`)
- **EventBridge**: Captures ECR image scan findings with CRITICAL or HIGH severity (rule created, SNS target commented out for future use)

### ECR Pull-Through Cache

Pull-through cache reduces external registry dependencies and egress costs. For authenticated registries (Docker Hub, GHCR), creating pull-through cache rules with credentials is the recommended approach — it avoids rate limits and provides reliable, cached access to upstream images.

- **Supported Upstream Registries**: Docker Hub, ECR Public, Quay.io, GCR, GHCR, Azure Container Registry (ACR). Enabled registries are configured via `ecr_pull_through_cache_upstream_registries`.
- **ACR Credentials**: Terraform creates the secret *container* only — `aws_secretsmanager_secret.acr_credentials`, named `ecr-pullthroughcache/<registry-url>` — and never the value, so the credentials never enter Terraform state or a plan file. The value is a JSON object with `username` and `password`, written by `scripts/deploy-with-acr.sh` (which reads them from 1Password) or by the secret-seeding script. A resource policy grants the ECR service-linked role access to the secret.
- **Rotating ACR credentials**: re-run `./scripts/deploy-with-acr.sh compute <env>`, or write the value directly. Either way `put-secret-value` adds a new version against the same ARN, so the pull-through cache rules keep resolving and **no Terraform change is needed**.
- **ACR Alias**: Automatically extracted from `acr_registry_url` (e.g., `myregistry` from `myregistry.azurecr.io`), registered as both the full URL and the short alias
- **Conditional**: ACR-related cache rules are skipped entirely if `acr_registry_url` is empty
- **Must match exactly**: the ACR entries in `ecr_pull_through_cache_upstream_registries` (the full `<registry>.azurecr.io` hostname and its short alias) must equal `acr_registry_url` and the alias derived from it. Entries with no known upstream URL are dropped without error, so a mismatch shows up only as unpullable application images; the `check` block in `ecr.tf` raises a warning when this happens. `06-applications/scripts/configure-instance.sh` rewrites the registry list and the root `common.auto.tfvars` `acr_registry_url` together to keep them in step.

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
- **Security Groups**: Cluster SG (443 from VPC endpoints, nodes, management server; NLB if present) + Nodes SG (standalone rules: self, VPC CIDR, cluster; attached via launch template)
- **Launch Template**: Per node group — attaches nodes SG, encrypted gp3 EBS (KMS), IMDSv2 enforced (hop limit 2)
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
- **Nodes**: Private subnets, standalone SG rules (self, VPC CIDR, cluster), attached via launch template
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

All scanner findings are either fixed or explicitly suppressed with rationale. Inline `#checkov:skip` comments and `.trivyignore.yaml` entries reference the central security baseline document. Sandbox relaxations and SCP enforcement recommendations are also documented there.

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
