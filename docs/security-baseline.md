# Security Baseline

This document is the single source of truth for all suppressed security scanner findings and sandbox (sbx) environment relaxations across the hello-aws landing zone. Each suppression includes rationale and, where applicable, the corresponding Service Control Policy (SCP) recommendation to enforce the production baseline.

This is a living document. Security posture is being hardened on an ongoing basis as the platform matures. Suppressions are reviewed regularly and removed as fixes are implemented. The goal is zero suppressions — every entry here represents either an AWS API limitation or a deliberate, risk-accepted trade-off with a compensating control.

## Suppressed Scanner Findings

### 01-bootstrap

#### Checkov

| Rule | Resource | Rationale |
|---|---|---|
| CKV_AWS_109 | `aws_kms_key.terraform_state` | KMS key policy grants root account permissions management to prevent lockout — required for key administration |
| CKV_AWS_111 | `aws_kms_key.terraform_state` | KMS key policy grants root account write access to manage key lifecycle — required for key administration |
| CKV_AWS_356 | `aws_kms_key.terraform_state` | KMS key policy uses `Resource: *` which is self-referential (refers to the key itself, not all resources) |

### 05-compute

#### Trivy (`.trivyignore`)

| Rule | Severity | Resource | Rationale |
|---|---|---|---|
| AWS-0040 | CRITICAL | `aws_eks_cluster.main` | `endpoint_public_access` is variable-driven (default `false`); only sbx overrides to `true` for development access |
| AWS-0041 | CRITICAL | `aws_eks_cluster.main` | `public_access_cidrs` is variable-driven; defaults to `[]` when public access is disabled |

#### Checkov

| Rule | Resource | Rationale |
|---|---|---|
| CKV_AWS_91 | `aws_lb.cloudfront`, `aws_lb.websocket` | ALB access logging deferred until S3 log bucket is provisioned |
| CKV_AWS_2 | `aws_lb_listener.cloudfront_http` | Internal ALB HTTP listener by design — TLS terminates at CloudFront VPC Origin, ALB forwards to Kong NLB over private network |
| CKV_AWS_163 | `aws_ecr_repository.main` | `scan_on_push` is variable-driven per repo; registry-level enhanced scanning provides continuous coverage |
| CKV_AWS_51 | `aws_ecr_repository.main` | `image_tag_mutability` is intentionally variable-driven per repo |
| CKV_AWS_338 | `aws_cloudwatch_log_group.eks_cluster` | Retention is variable-driven per environment (7d sbx, 30d default, 365d prod) |
| CKV_AWS_355 | `cert_manager_route53`, `speech` | Route53 List and Transcribe actions do not support resource-level constraints (AWS API limitation) |
| CKV_AWS_290 | `speech` | Transcribe write actions do not support resource-level constraints (AWS API limitation) |

## Sandbox Environment Relaxations

The following settings are overridden in sbx `00-config.auto.tfvars` to enable fast iteration, teardown, and development access. These relaxations **must not** be applied to production workload accounts.

### 01-bootstrap

| Setting | sbx Value | Production Default | Risk |
|---|---|---|---|
| `kms_deletion_window` | `0` (immediate) | `30` days | KMS keys deleted without recovery window |
| `cloudwatch_log_retention_days` | `7` days | `30` days | Reduced audit trail |

### 03-infrastructure

| Setting | sbx Value | Production Default | Risk |
|---|---|---|---|
| `kms_deletion_window` | `0` (immediate) | `30` days | KMS keys deleted without recovery window |
| `cloudwatch_log_retention_days` | `7` days | `30` days | Reduced audit trail |
| `availability_zone_count` | `2` | `3` | Reduced availability |
| `single_nat_gateway` | `true` | `false` | Single point of failure for egress |
| `management_server_monitoring` | `false` | `true` | No detailed CloudWatch monitoring on bastion |

### 04-data-and-ai

| Setting | sbx Value | Production Default | Risk |
|---|---|---|---|
| `secrets_recovery_window_days` | `0` (immediate) | `30` days | Secrets deleted without recovery window |
| `aurora_deletion_protection` | `false` | `true` | Database can be accidentally deleted |
| `aurora_skip_final_snapshot` | `true` | `false` | No final snapshot on deletion — data loss |
| `aurora_instance_count` | `1` | `2` | No read replica, reduced availability |
| `elasticache_automatic_failover_enabled` | `false` | `true` | No automatic failover on failure |
| `elasticache_multi_az_enabled` | `false` | `true` | Single-AZ cache, no redundancy |
| `elasticache_snapshot_retention_limit` | `1` day | `5` days | Reduced backup retention |

### 05-compute

| Setting | sbx Value | Production Default | Risk |
|---|---|---|---|
| `eks_endpoint_public_access` | `true` | `false` | EKS API accessible from internet |
| `eks_endpoint_public_access_cidrs` | `["0.0.0.0/0"]` | `[]` | No CIDR restriction on public access |
| `eks_cluster_log_retention_days` | `7` days | `365` days (recommended) | Reduced audit trail for compliance |
| `alb_deletion_protection` | `false` | `true` | ALBs can be accidentally deleted |

## Production Guardrails via SCP

The sbx relaxations above should be enforced at the AWS Organizations level using Service Control Policies (SCPs). SCPs act as a preventive guardrail — even if Terraform configuration is misconfigured, the AWS API will deny the action in production accounts.

### Recommended SCPs

| SCP | Layers Affected | AWS Actions to Deny | Condition |
|---|---|---|---|
| Enforce KMS minimum deletion window | 01-bootstrap, 03-infrastructure | `kms:ScheduleKeyDeletion` | `kms:PendingWindowInDays` < 7 |
| Enforce Secrets Manager recovery window | 04-data-and-ai | `secretsmanager:DeleteSecret` | `secretsmanager:RecoveryWindowInDays` < 7 |
| Deny RDS deletion without protection | 04-data-and-ai | `rds:DeleteDBCluster` | When `deletion_protection` is `false` |
| Enforce RDS final snapshot | 04-data-and-ai | `rds:DeleteDBCluster` | When `SkipFinalSnapshot` is `true` |
| Deny public EKS endpoints | 05-compute | `eks:CreateCluster`, `eks:UpdateClusterConfig` | When `endpointPublicAccess` is `true` |
| Deny disabling ALB deletion protection | 05-compute | `elasticloadbalancing:ModifyLoadBalancerAttributes` | When `deletion_protection.enabled` is `false` |
| Deny public ELB creation | 05-compute | `elasticloadbalancing:CreateLoadBalancer` | When `scheme` is `internet-facing` (unless tagged `AllowPublic=true`) |
| Enforce EBS encryption by default | 05-compute | `ec2:DisableEbsEncryptionByDefault` | Unconditional deny |
| Enforce ECR immutable tags | 05-compute | `ecr:PutImageTagMutability` | When `imageTagMutability` is `MUTABLE` |
| Enforce CloudWatch monitoring | 03-infrastructure | `ec2:RunInstances` | When `monitoring.enabled` is `false` |

### Enforcement Strategy

SCPs are applied at the Organizational Unit (OU) level in AWS Organizations:

```
Root
  +-- Production OU          <-- All SCPs above attached here
  |     +-- prod accounts
  |     +-- stag accounts
  +-- Non-Production OU
  |     +-- dev accounts      <-- Subset of SCPs (KMS, Secrets Manager, RDS protection)
  +-- Sandbox OU              <-- No restrictive SCPs (fast iteration)
        +-- sbx accounts
```

This ensures the Terraform code remains environment-agnostic (variable-driven defaults are secure) while the organization boundary prevents accidental or intentional relaxation in production.

### Implementation Priority

1. **P0 (immediate)**: KMS deletion window, RDS deletion protection, RDS final snapshot, Secrets Manager recovery window — prevent irreversible data loss
2. **P1 (before prod)**: Public EKS endpoint, EBS encryption, ALB deletion protection — prevent exposure and accidental deletion
3. **P2 (hardening)**: ECR immutable tags, public ELB creation, CloudWatch monitoring — defense in depth
