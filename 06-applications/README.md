# 06-applications — ArgoCD-Managed Applications

ArgoCD-managed Kubernetes applications on EKS. This layer is a **forkable template** —
the `main` branch contains `<PLACEHOLDER>` tokens that are replaced with real values
on the deployment branch. Each environment has its own folder (`sbx/`, `prod/`, etc.)
so a single `deploy` branch supports multiple environments.

## Quick Start

```bash
# 1. Fork the repository
# 2. Create the deployment branch
git checkout -b deploy

# 3. Create instance configuration for your environment
cp 06-applications/instance-config.yaml.template 06-applications/sbx/instance-config.yaml
# Edit sbx/instance-config.yaml with your values (targetRevision: deploy)

# 4. Apply configuration (replaces placeholders in sbx/ only)
cd 06-applications
./scripts/configure-instance.sh sbx
./scripts/validate-instance.sh sbx    # confirm no placeholders remain

# 5. Commit and push
cd ..
git add -A && git commit -m "configure: apply sbx instance values"
git push -u origin deploy

# 6. Bootstrap ArgoCD
cd 06-applications
helmfile -e sbx -f argo-bootstrap.yaml sync
```

## Branch Model

| Branch | Purpose | Contains |
|--------|---------|----------|
| `main` | Forkable template | `<PLACEHOLDER>` tokens — never deployed directly |
| `deploy` | Deployment branch | Real values per env folder — ArgoCD watches this branch |
| `feat/*` | Feature/PR branches | Merge to `main` via PR train |

Each environment folder (`sbx/`, `prod/`) is configured independently:
1. Fork repo — `main` has placeholders
2. `git checkout -b deploy`
3. `cp instance-config.yaml.template sbx/instance-config.yaml` — fill in real values
4. `./scripts/configure-instance.sh sbx` — replaces placeholders in `sbx/` only
5. Commit to `deploy` branch — ArgoCD watches it

Adding a second environment (e.g. `prod/`):
1. Copy `sbx/` to `prod/` on the `deploy` branch
2. `cp instance-config.yaml.template prod/instance-config.yaml` — fill in prod values
3. `./scripts/configure-instance.sh prod` — replaces placeholders in `prod/` only
4. Each cluster's ArgoCD points to its own env folder via ApplicationSet paths

## Configuration Reference

All parameters in `<env>/instance-config.yaml`:

| Parameter | Token | Description |
|-----------|-------|-------------|
| `github.repoURL` | `<GITHUB_REPO_URL>` | Fork's GitHub URL |
| `github.targetRevision` | `<GIT_TARGET_REVISION>` | Deployment branch name (e.g. `deploy`) |
| `domain.base` | `<DOMAIN_BASE>` | Base domain (e.g. `sbx.example.com`) |
| `domain.api` | `<DOMAIN_API>` | API domain (e.g. `api.sbx.example.com`) |
| `domain.identity` | `<DOMAIN_IDENTITY>` | Identity provider domain (e.g. `id.sbx.example.com`) |
| `domain.argocd` | `<DOMAIN_ARGOCD>` | ArgoCD UI domain (e.g. `argo.sbx.example.com`) |
| `domain.dnsZone` | `<DNS_ZONE>` | DNS zone for cert-manager (e.g. `example.com`) |
| `aws.region` | `<AWS_REGION>` | AWS region (e.g. `eu-central-2`) |
| `aws.hostedZoneID` | `<AWS_HOSTED_ZONE_ID>` | Route 53 hosted zone ID |
| `aws.kms.keyArn` | `<KMS_KEY_ARN>` | KMS key ARN for EBS encryption |
| `aws.ecr.primary.accountId` | Part of `<ECR_REGISTRY_PRIMARY>` | ECR account for app images |
| `aws.ecr.primary.prefix` | Part of `<ECR_REGISTRY_PRIMARY>` | ECR repository prefix |
| `aws.ecr.thirdParty.accountId` | Part of `<ECR_REGISTRY_THIRDPARTY>` | ECR account for infra images |
| `aws.ecr.thirdParty.prefix` | Part of `<ECR_REGISTRY_THIRDPARTY>` | ECR repository prefix |
| `zitadel.projectId` | `<ZITADEL_PROJECT_ID>` | Zitadel project ID |
| `zitadel.clientId` | `<ZITADEL_CLIENT_ID>` | Zitadel client ID |
| `zitadel.orgId` | `<ZITADEL_ORG_ID>` | Zitadel organization ID |

## Directory Structure

```
06-applications/
├── argo-bootstrap.yaml              # Helmfile: bootstraps ArgoCD + ApplicationSets
├── instance-config.yaml.template    # Configuration template (copy into env dir)
├── scripts/
│   ├── configure-instance.sh        # Replace placeholders (env-scoped)
│   └── validate-instance.sh         # Verify no placeholders remain (env-scoped)
├── defaults/                        # Base app configurations (env-independent)
│   ├── ai-services/
│   ├── backend-services/
│   └── web-apps/
└── sbx/                             # Environment-specific configuration
    ├── instance-config.yaml         # (gitignored) Real values for this env
    ├── apps/
    │   ├── system/                   # System app specs (12 apps)
    │   └── chat/                     # Chat app specs (21 apps)
    ├── charts/
    │   ├── backend-service/          # Local Helm chart for backend services
    │   └── web-app/                  # Local Helm chart for web apps
    └── values/
        ├── _common.yaml              # Shared values (ECR registry)
        ├── argo/                     # ArgoCD + ApplicationSet values
        ├── cert-manager/             # cert-manager + ClusterIssuer
        ├── external-secrets/         # ESO + ClusterSecretStore + app secrets
        ├── kong/                     # Kong controller, gateway, ingress, plugins
        ├── storage-class/            # gp3 StorageClass
        ├── reloader/                 # Stakater Reloader
        ├── aws-lb-controller/        # AWS Load Balancer Controller
        ├── keda/                     # KEDA autoscaler
        ├── elasticsearch/            # Elasticsearch
        ├── rabbitmq-operator/        # RabbitMQ Cluster Operator
        ├── rabbitmq/                 # RabbitMQ cluster instance
        ├── qdrant/                   # Qdrant vector database
        ├── litellm/                  # LiteLLM proxy (LLM gateway)
        ├── zitadel/                  # Zitadel identity provider
        ├── ai-services/              # AI service values
        ├── backend-services/         # Backend service values
        └── web-apps/                 # Web app values
```

## ArgoCD Bootstrap

Bootstrap ArgoCD and ApplicationSets on the deployment branch:

```bash
cd 06-applications
helmfile -e sbx -f argo-bootstrap.yaml sync
```

This deploys:
1. **ArgoCD** (`argo/argo-cd` chart) — GitOps controller, admin-only access (no SSO)
2. **ApplicationSets** (`argo/argocd-apps` chart) — two ApplicationSets that discover apps from Git:
   - `system` — watches `sbx/apps/system/*.yaml`
   - `chat` — watches `sbx/apps/chat/*.yaml`

ArgoCD UI is accessible at `https://<DOMAIN_ARGOCD>` (admin password from initial secret).

## Application Categories

### System Applications (12)

| App | autoSync | Description |
|-----|----------|-------------|
| storage-class-gp3 | true | gp3 StorageClass for EBS CSI Driver |
| cert-manager | true | TLS certificate management with Route 53 DNS-01 validation |
| external-secrets | false | AWS Secrets Manager integration (ClusterSecretStore + app secrets) |
| reloader | true | Automatic pod restart on ConfigMap/Secret changes |
| kong | false | API gateway — controller, gateway, CRDs, plugins, ingress |
| rabbitmq-operator | false | RabbitMQ Cluster Operator |
| eck | true | Elastic Cloud on Kubernetes operator (single-source, no values) |
| elasticsearch | false | Elasticsearch cluster |
| zitadel | false | Identity provider (ExternalSecrets for DB credentials) |
| argocd | false | ArgoCD self-management |
| aws-lb-controller | true | AWS Load Balancer Controller (NLB/ALB provisioning) |
| keda | true | Event-driven autoscaling (ServerSideApply for CRDs) |

### Chat Applications (21)

All chat apps have `autoSync: false`. They include:

**Backend Services:** scope-management, chat, ingestion, ingestion-worker, ingestion-worker-chat,
app-repository, configuration, event-socket, speech, webhook-scheduler, webhook-worker,
client-insights-exporter

**AI Services:** assistants-core, ingestor

**Web Apps:** chat, admin, knowledge-upload, theme

**Data:** rabbitmq (cluster instance), qdrant (vector database), litellm (LLM gateway + embedding proxy)

## LiteLLM — Bedrock Model Configuration

LiteLLM proxies all LLM and embedding traffic through AWS Bedrock. Models are configured
in `values/litellm/litellm.yaml` under `proxy_config.model_list`.

**Chat/completion models** use EU cross-region inference profiles (`eu.*` prefix) directly:
```yaml
model: bedrock/eu.anthropic.claude-sonnet-4-5-20250929-v1:0
```

**Embedding models** require an application inference profile because:
1. Cohere Embed v4 requires an inference profile for on-demand invocation
2. LiteLLM's provider mapping (`model.split(".")[0]`) breaks with the `eu.*` prefix for embeddings

The workaround uses `model` for provider mapping and `model_id` for the Bedrock API call:
```yaml
- model_name: text-embedding-ada-002
  litellm_params:
    model: bedrock/cohere.embed-v4:0                    # provider mapping -> "cohere"
    model_id: arn:aws:bedrock:<AWS_REGION>:<AWS_ACCOUNT_ID>:application-inference-profile/<PROFILE_ID>
    aws_region_name: <AWS_REGION>
```

The application inference profile wraps the `global.cohere.embed-v4:0` system profile and
is created in `04-data-and-ai/terraform/bedrock.tf`. The `model_id` ARN is environment-specific
and must be set per deployment.

**Key settings:**
- `drop_params: true` — silently drops unsupported parameters (e.g. `encoding_format: 'float'`)
- Image tag is pinned explicitly (not tied to chart version)

## Pod Identities

Workloads that require AWS EKS Pod Identity (pre-provisioned in `05-compute/terraform/iam.tf`):

### System

| Service Account | Namespace | AWS Access | Purpose |
|----------------|-----------|------------|---------|
| `cert-manager` | unique | Route 53 | DNS-01 certificate validation |
| `external-secrets` | unique | Secrets Manager + KMS | Secret retrieval |
| `ebs-csi-controller-sa` | kube-system | EBS | Volume provisioning (EKS addon, not ArgoCD-managed) |

### Chat

| Service Account | Namespace | AWS Access | Purpose |
|----------------|-----------|------------|---------|
| `assistants-core` | unique | Bedrock, S3, Secrets Manager | LLM inference + AI data storage |
| `litellm` | unique | Bedrock | Unified LLM proxy (Claude via Bedrock) |
| `backend-service-ingestion` | unique | S3 | Document upload and storage |
| `backend-service-ingestion-worker` | unique | Bedrock, S3 | AI-powered document processing |
| `backend-service-speech` | unique | Transcribe | Speech-to-text |

> **Note:** The chat backend service uses static S3 credentials (IAM user, not Pod Identity) stored
> in Secrets Manager, required by the S3BucketStrategy pattern. Defined in
> `04-data-and-ai/terraform/iam-s3-access.tf`.

## Adding a New Workload

1. **Create app spec** in `sbx/apps/system/` or `sbx/apps/chat/`:
   ```yaml
   spec:
     name: my-service
     autoSync: false
     sources:
       - repoURL: '<GITHUB_REPO_URL>'
         targetRevision: <GIT_TARGET_REVISION>
         ref: values
       - chart: my-chart
         repoURL: https://charts.example.com
         targetRevision: 1.0.0
         helm:
           releaseName: my-service
           valueFiles:
             - $values/06-applications/sbx/values/my-service/values.yaml
   ```

2. **Create values file** in `sbx/values/my-service/values.yaml`

3. If needed, add **default values** in `defaults/` (environment-independent config)

4. Commit to deployment branch — ApplicationSet auto-discovers the new app

## Scripts Reference

| Script | Purpose |
|--------|---------|
| `scripts/configure-instance.sh <env>` | Replace `<PLACEHOLDER>` tokens with real values from `<env>/instance-config.yaml`. Only modifies files under `<env>/`. Idempotent — tracks applied state in `<env>/.instance-applied.yaml`. |
| `scripts/validate-instance.sh <env>` | Verify no placeholder tokens remain in `<env>/` YAML files. Exit 0 = clean, exit 1 = tokens found. |
