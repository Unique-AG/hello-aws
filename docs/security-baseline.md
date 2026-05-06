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
| CKV_AWS_144 | `aws_s3_bucket.terraform_state`, `aws_s3_bucket.access_logs` | Cross-region replication intentionally not enabled. The landing zone is single-region by design (one AWS region per workload account) — terraform state lives in the same region as the resources it manages, and access logs trace activity in the same region. CRR would double storage cost and add a second-region IAM/KMS surface without giving Terraform a usable failover (state file conflicts during a region-loss recovery would block apply anyway). DR posture for state is point-in-time restore via S3 versioning + KMS-encrypted snapshots, not active-active. **Re-evaluate if multi-region becomes a requirement.** |
| CKV2_AWS_62 | `aws_s3_bucket.terraform_state`, `aws_s3_bucket.access_logs` | S3 Event Notifications intentionally not configured. Both buckets are write-many/read-rarely storage destinations: terraform state is read by `terraform init/plan/apply` only, and access logs are written by S3 itself. Neither has a downstream event consumer (no Lambda, SQS, SNS, EventBridge wiring would trigger meaningful work on object events). Adding notifications would surface `ConfigurationNotFound` warnings and incur API/event costs without observable signal. CloudTrail data events provide audit-grade visibility if needed. |

### 03-infrastructure

#### Trivy

| Rule | Severity | Resource | Rationale |
|---|---|---|---|
| AVD-AWS-0053 | HIGH | `aws_lb.websocket` | Public-facing by design — WebSocket ALB serves client connections that cannot traverse CloudFront |
| AVD-AWS-0054 | CRITICAL | `aws_lb_listener.cloudfront_http` | Internal ALB HTTP listener by design — TLS terminates at CloudFront VPC Origin, HTTP is sufficient for private VPC traffic |
| AVD-AWS-0104 | CRITICAL | `aws_security_group.github_runners` | Runners require HTTPS (443) egress to `0.0.0.0/0` for GitHub API and package registries; scoped to port 443 only |

#### Checkov

| Rule | Resource | Rationale |
|---|---|---|
| CKV_AWS_91 | `aws_lb.ingress_nlb`, `aws_lb.websocket` | ALB access logging deferred — requires dedicated S3 log bucket with ELB write policy. CloudFront access logs provide partial coverage for the internal ALB. Public WebSocket ALB has no compensating control. **Remediation: provision log bucket before production.** |
| CKV_AWS_103 | `aws_lb_listener.cloudfront_http` | Listener is HTTP-only by design — it is the CloudFront VPC Origin's HTTP→ingress hop. CloudFront terminates TLS (TLS 1.2+) at the edge; the VPC Origin → ALB segment is private VPC-internal traffic. Setting `ssl_policy` is not applicable to an `HTTP` protocol listener. **Compensating control:** CloudFront's `viewer_minimum_protocol_version` enforces TLS 1.2+ for all client-facing TLS. |
| CKV_AWS_150 | `aws_lb.ingress_nlb` | Deletion protection controlled by `var.alb_deletion_protection`; disabled in sandbox for fast teardown |
| CKV_AWS_290 | `aws_iam_role_policy.connectivity_transit_gateway` | EC2 Describe and transit gateway actions do not support resource-level constraints (AWS API limitation) |
| CKV_AWS_355 | `aws_iam_role_policy.connectivity_transit_gateway` | EC2 Describe and transit gateway actions require `Resource: *` (AWS API limitation) |
| CKV_AWS_338 | `aws_cloudwatch_log_group.vpc_flow_logs` | Retention is variable-driven per environment (7d sbx, 30d default, 365d prod) |
| CKV_AWS_378 | `aws_lb_target_group.ingress_nlb`, `aws_lb_target_group.websocket_ingress` | Target groups carry `protocol = "HTTP"` because the path is CloudFront/WebSocket-ALB → **target group HTTP** → ingress controller pod. End-to-end transport security is preserved: CloudFront edge terminates TLS 1.2+ for clients, and the in-VPC hop from ALB → ingress controller is over private subnets only. Bumping the TG protocol to HTTPS would require terminating TLS again at the ingress controller for the same path, doubling cert management without changing the threat model. |
| CKV2_AWS_5 | `aws_security_group.alb_cloudfront`, `aws_security_group.alb_websocket`, `aws_security_group.ingress_nlb` | All three SGs are conditionally created (`count = var.enable_ingress_nlb ? 1 : 0`) and attached when active. Checkov's graph check evaluates each `count = 0` instantiation as orphaned because no resource references the (non-existent) SG, and surfaces `count = 1` cases when the dependent ALB/NLB declarations are also under the same `count`. Verified by inspection: `aws_lb.cloudfront[0]`, `aws_lb.websocket[0]`, and the ingress NLB target groups attach these SGs whenever `enable_ingress_nlb` is true. |
| CKV2_AWS_28 | `aws_lb.websocket` | The WebSocket ALB is internet-facing but **proxied by CloudFront** (not directly client-reachable). All inbound traffic is routed through CloudFront, which sits in front of the AWS WAF Web ACL. The compensating control (WAF on the CloudFront distribution, not the ALB) provides equivalent protection. Direct ALB access from non-CloudFront clients would be possible if the SG were misconfigured, but the SG (`aws_security_group.alb_websocket`) only allows ingress from CloudFront prefix list. **Re-evaluate** if the ALB is ever exposed without CloudFront in front. |

### 04-data-and-ai

#### Checkov

| Rule | Resource | Rationale |
|---|---|---|
| CKV_AWS_162 | `aws_rds_cluster.postgres` | Zitadel uses password-based auth managed via AWS Secrets Manager (`manage_master_user_password`); Zitadel's Go database driver (`internal/database/postgres/pg.go`) hardcodes username/password auth with no extensibility point for IAM token-based auth |
| CKV_AWS_118 | `aws_rds_cluster_instance.postgres` | Enhanced monitoring deferred — requires a dedicated IAM role (trivial to create). CloudWatch metrics and Performance Insights provide baseline observability; Enhanced Monitoring adds OS-level metrics (process CPU, memory, disk I/O). **Remediation: add IAM role + `monitoring_interval` before production.** |
| CKV_AWS_31 | `aws_elasticache_replication_group.redis` | No AUTH token — risk accepted. Compensating controls: VPC isolation (isolated subnets), security group restricts to VPC CIDR, TLS enabled, KMS at-rest encryption. Residual risk: any VPC-internal process can execute Redis commands without authentication. **Remediation: evaluate RBAC or IAM auth for defense-in-depth before production.** |
| CKV_AWS_273 | `aws_iam_user.s3_access` | Chat service `S3BucketStrategy` (Node.js `@unique-ag/chat`) uses a non-standard S3 client requiring explicit access keys; AWS SDK default credential chain (IRSA/Pod Identity) not supported by this client. Compensating controls: keys stored in Secrets Manager with KMS encryption, IAM policy scoped to specific S3 buckets and KMS key. **Technical debt: evaluate migrating to an AWS SDK-compatible client to enable Pod Identity.** |
| CKV_AWS_18 | `aws_s3_bucket.observability`, `aws_s3_bucket.application_data`, `aws_s3_bucket.ai_data` | Per-bucket S3 access logging would create a per-bucket access-logs companion (each itself failing CKV_AWS_18 → chicken-egg). Audit signal is provided by **CloudTrail S3 data events** at the org level, which captures object-level read/write API calls with caller identity, source IP, and request parameters — strictly more useful than S3 access logs for security investigation. **Remediation prerequisite:** confirm CloudTrail data events are enabled at the org (CloudTrail trail with `data_resource = "AWS::S3::Object"` or equivalent management trail). |
| CKV_AWS_144 | `aws_s3_bucket.observability`, `aws_s3_bucket.application_data`, `aws_s3_bucket.ai_data` | Same as 01-bootstrap rationale — single-region landing zone by design. Each workload account is provisioned in one AWS region; CRR would double storage cost and add second-region IAM/KMS surface for marginal DR value. State, observability data, and application data are reproducible from primary sources (logs/metrics from the running cluster, application data from RDS PITR + EBS snapshots) under a region-loss recovery scenario. **Re-evaluate if multi-region becomes a requirement.** |
| CKV2_AWS_5 | `aws_security_group.grafana` | Conditionally created (`count = var.enable_managed_grafana ? 1 : 0`); attached to the AWS Managed Grafana workspace (`aws_grafana_workspace.main[0]`) via `vpc_configuration.security_group_ids` when active. Same false-positive pattern as 03-infrastructure conditional SGs. |
| CKV2_AWS_8 | `aws_rds_cluster.postgres` | Aurora cluster uses the managed RDS automated snapshot system (`backup_retention_period`, `preferred_backup_window`) plus `final_snapshot_identifier` on destroy. AWS Backup overlay would duplicate snapshots into a separate Backup Vault — useful for cross-account/cross-region backup centralization, but the landing zone is single-account and (per CKV_AWS_144 rationale) single-region. AWS Backup adds a second IAM/KMS surface and ~2× storage cost for snapshots that already exist in the RDS snapshot store. **Re-evaluate** when org centralizes backups via AWS Organizations + AWS Backup vaults. |
| CKV2_AWS_27 | `aws_rds_cluster.postgres` | Postgres query logging (`log_statement = all` or `pgaudit`) generates substantial CloudWatch Logs volume (approx. 1 line per statement × hundreds of QPS) at meaningful cost. Audit needs are met by CloudTrail RDS data events (cluster-level admin actions) + Performance Insights (slow queries, top queries by latency/wait). Statement-level logging is appropriate for compliance audits (PCI-DSS, HIPAA) but not as a default. **Remediation:** if compliance scope requires statement logging, set the cluster's `enabled_cloudwatch_logs_exports` to include `postgresql` and configure `pgaudit` parameters. |
| CKV2_AWS_57 | All `aws_secretsmanager_secret.*` (37 secrets across `iam-s3-access.tf`, `observability-storage.tf`, `secrets.tf`) | Most secrets in this layer store **immutable infrastructure facts or externally-rotated credentials**, which the Secrets Manager rotation lambda model can't safely rotate: (a) infrastructure facts (psql host/port, redis host/port, S3 bucket names/ARNs/endpoints/region, observability bucket) are derived from terraform-managed AWS resources and only change on terraform apply; (b) externally-rotated credentials (zitadel master key, encryption keys, S3 access keys, registry credentials, Slack webhook URL, Google Search API key, ArgoCD GitHub App, RabbitMQ password, LiteLLM master/salt keys, RDS CA bundle, Grafana admin password, Azure OpenAI endpoint definitions) are rotated by their issuing systems (Zitadel, GitHub App, Bitnami operator, etc.) on schedules outside Secrets Manager's awareness. A rotation lambda would either (a) overwrite externally-managed secrets with regenerated values that immediately fail upstream verification, or (b) require a custom rotation handler per secret type — significant complexity for marginal value. **Compensating controls:** all secrets are KMS-encrypted, recovery-window-protected, and accessed via IRSA-scoped IAM with read-only paths. **Re-evaluate per secret** if/when an upstream system supports SM-driven rotation. |
| CKV2_AWS_62 | `aws_s3_bucket.observability`, `aws_s3_bucket.application_data`, `aws_s3_bucket.ai_data` | Buckets are storage destinations for batch and stream writes from in-cluster workloads (Loki/Tempo for observability, ingestion pipelines for application/AI data). No Lambda, SQS, SNS, or EventBridge rule consumes object-create events from these buckets — adding S3 Event Notifications would emit events with no subscriber, producing CloudWatch noise without observable signal. If a future workflow needs reactive processing on object writes, configure Event Notifications + a target at that point. |

### 05-compute

#### Trivy (`.trivyignore`)

| Rule | Severity | Resource | Rationale |
|---|---|---|---|
| AWS-0040 | CRITICAL | `aws_eks_cluster.main` | `endpoint_public_access` is variable-driven (default `false`); only sbx overrides to `true` for development access |
| AWS-0041 | CRITICAL | `aws_eks_cluster.main` | `public_access_cidrs` is variable-driven; defaults to `[]` when public access is disabled |

#### Checkov

| Rule | Resource | Rationale |
|---|---|---|
| CKV_AWS_163 | `aws_ecr_repository.main` | `scan_on_push` is variable-driven per repo; registry-level enhanced scanning (`CONTINUOUS_SCAN` with `*` filter) provides strictly superior coverage — re-evaluates images when new CVEs are published |
| CKV_AWS_51 | `aws_ecr_repository.main` | `image_tag_mutability` is variable-driven per repo to support CI/CD patterns using mutable tags (e.g., `latest`, branch tags). Production repos should use `IMMUTABLE` tags; enforced via SCP (see below) |
| CKV_AWS_111 | `speech`, `aws_lb_controller` | `speech`: Transcribe streaming actions (`StartStreamTranscription`, `StartTranscriptionJob`) do not support resource-level constraints (AWS API limitation). `aws_lb_controller`: dynamically manages ELB/EC2 resources whose ARNs cannot be predetermined; tag-based conditions recommended for production hardening (see [official policy](https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/main/docs/install/iam_policy.json)) |
| CKV_AWS_290 | `speech`, `aws_lb_controller` | Same rationale as CKV_AWS_111 — write actions that either lack resource-level support (Transcribe) or require dynamic resource creation (LB controller) |
| CKV_AWS_355 | `cert_manager_route53`, `speech`, `aws_lb_controller` | `cert_manager_route53`: `ListHostedZones` and `ListHostedZonesByName` do not support resource-level constraints (AWS API limitation). `speech` and `aws_lb_controller`: same rationale as CKV_AWS_111 |
| CKV_AWS_356 | `cert_manager_route53`, `speech`, `aws_lb_controller` | Same resources as CKV_AWS_355 — checkov flags `*` for actions it considers restrictable, but these are either genuinely unscopable (Route53 List, Transcribe streaming) or dynamically managed (LB controller) |
| CKV_AWS_341 | `aws_launch_template.eks_nodes` | IMDS hop limit set to 2 — required for EKS. Pods access the instance metadata service through the node's network namespace, adding one network hop. AWS recommends `http_put_response_hop_limit = 2` for containerized workloads. IMDSv2 (`http_tokens = required`) is enforced. |
| CKV_AWS_24, CKV_AWS_25, CKV_AWS_260 | `aws_vpc_security_group_ingress_rule.eks_nodes_self` | Checkov false positive — rule uses `referenced_security_group_id` (self-referencing, node-to-node only), not `0.0.0.0/0`. Checkov's `AbsSecurityGroupUnrestrictedIngress` does not recognize `referenced_security_group_id` on `aws_vpc_security_group_ingress_rule` resources ([checkov#6624](https://github.com/bridgecrewio/checkov/issues/6624)). |
| CKV2_AWS_57 | `aws_secretsmanager_secret.acr_credentials` | The secret stores Azure Container Registry credentials used by ECR pull-through cache. The credentials are issued and rotated by **Azure** (the upstream registry), not by AWS Secrets Manager. A rotation lambda would either (a) overwrite the secret with regenerated values that fail Azure auth, or (b) require a custom handler that authenticates to Azure to issue a new ACR token — significant complexity for a low-volume secret that's bound to ACR's own rotation cadence. The seed-secrets.sh script populates the value from 1Password, mirroring Azure's rotation. **Compensating controls:** KMS-encrypted, IRSA-scoped IAM read access from EKS only. |

### 06-applications

#### Helm Values

| Setting | Chart | Rationale |
|---|---|---|
| `global.security.allowInsecureImages: true` | `rabbitmq-operator` | Bitnami legacy images (`bitnamilegacy/rabbitmq-cluster-operator`, `bitnamilegacy/rmq-messaging-topology-operator`) are not signed. Cosign signature verification fails for these images. **Remediation: migrate to signed Bitnami images or a private registry with enforced signing before production.** |

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
