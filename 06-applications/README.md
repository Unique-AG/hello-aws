# 06-applications Layer

## Overview

The applications layer contains Kubernetes application manifests and Helmfile configurations for deploying containerized applications to the EKS cluster. This layer uses GitOps principles with ArgoCD for automated application deployment and management.

## Design Rationale

### GitOps Architecture

The applications layer follows **GitOps principles**:

- **Declarative Configuration**: All application configurations defined as code
- **Version Control**: All changes tracked in Git
- **Automated Deployment**: ArgoCD automatically syncs applications
- **Environment Separation**: Separate configurations per environment (dev, test, prod, sbx)

### ArgoCD Integration

ArgoCD provides **continuous deployment** for Kubernetes applications:

- **Application Management**: Declarative application definitions
- **Sync Automation**: Automatic synchronization of desired state
- **Multi-Environment**: Support for multiple environments
- **RBAC**: Role-based access control for application management

### Helmfile Structure

Applications are organized using **Helmfile** for Helm chart management:

- **Defaults**: Base application configurations
- **Environment Overrides**: Environment-specific values
- **System Applications**: Infrastructure applications (ArgoCD, cert-manager, etc.)
- **Application Services**: Business logic applications

### Application Categories

Applications are organized by category:

- **System Applications**: Infrastructure and platform services
  - ArgoCD, cert-manager, Kong, Elasticsearch, etc.
- **Backend Services**: Application backend services
  - Chat, ingestion, webhooks, etc.
- **Web Apps**: Frontend applications
  - Admin, chat UI, knowledge upload, etc.
- **AI Services**: AI/ML services
  - Assistants core, etc.

## Resources

### ArgoCD Applications

- **System Applications**: Infrastructure applications deployed via ArgoCD
- **Application Services**: Business applications deployed via ArgoCD
- **Application Sets**: Automated application discovery and deployment

### Helm Charts

Applications are deployed using Helm charts:

- **System Charts**: Infrastructure and platform services
- **Application Charts**: Business logic applications
- **Custom Charts**: Client-specific applications

### Configuration Management

- **Defaults**: Base configurations for all environments
- **Environment Values**: Environment-specific overrides
- **Secrets**: Managed via External Secrets Operator

## Security Principles

### Secrets Management

- **External Secrets**: Secrets retrieved from AWS Secrets Manager
- **KMS Encryption**: All secrets encrypted with customer-managed keys
- **RBAC**: Role-based access control for secret access
- **No Hardcoded Secrets**: All secrets externalized

### Access Control

- **ArgoCD RBAC**: Role-based access control for application management
- **Kubernetes RBAC**: Namespace-level access control
- **IAM Integration**: IRSA for AWS service access

### Network Security

- **Network Policies**: Kubernetes network policies for pod-to-pod communication
- **Service Mesh**: Kong API Gateway for ingress and API management
- **TLS/SSL**: Cert-manager for automatic certificate management

### Compliance

- **GitOps Audit Trail**: All changes tracked in Git
- **ArgoCD Audit Logs**: Application deployment audit logs
- **Version Control**: All configurations versioned

## Well-Architected Framework

### Operational Excellence

- **GitOps**: Declarative configuration with automated deployment
- **ArgoCD**: Continuous deployment and synchronization
- **Helmfile**: Structured Helm chart management
- **Documentation**: Clear application structure and deployment procedures

### Security

- **Secrets Management**: External Secrets Operator for secure secret handling
- **RBAC**: Role-based access control at multiple levels
- **Network Policies**: Pod-to-pod network segmentation
- **TLS/SSL**: Automatic certificate management

### Reliability

- **Multi-Environment**: Separate configurations for dev, test, prod
- **Health Checks**: ArgoCD health checks for applications
- **Rollback**: Git-based rollback capabilities
- **Monitoring**: Application metrics via Prometheus

### Performance Efficiency

- **Resource Management**: Configurable resource requests and limits
- **Auto Scaling**: Horizontal Pod Autoscaler (HPA) support
- **Caching**: Redis caching for performance optimization

### Cost Optimization

- **Resource Right-Sizing**: Configurable resource requests per environment
- **Auto Scaling**: Scale down during low usage
- **Environment Separation**: Cost tracking per environment

## Deployment

### Prerequisites

1. Compute layer (EKS cluster) must be deployed first
2. Data-and-ai layer should be deployed (for database access)
3. ArgoCD must be bootstrapped in the cluster

### ArgoCD Bootstrap

Bootstrap ArgoCD in the EKS cluster:

```bash
kubectl apply -f argo-bootstrap.yaml
```

This creates the initial ArgoCD installation and ApplicationSet for managing other applications.

### Application Structure

Applications are organized as follows:

```
06-applications/
├── defaults/              # Base application configurations
│   ├── backend-services/
│   ├── web-apps/
│   └── ai-services/
├── {env}/                 # Environment-specific overrides
│   ├── apps/              # Application definitions
│   └── values/            # Environment-specific values
└── system-helmfile.yaml   # System applications Helmfile
```

### Deployment Workflow

1. **Bootstrap ArgoCD**: Deploy ArgoCD to the cluster
2. **Configure Applications**: Update application configurations in Git
3. **ArgoCD Sync**: ArgoCD automatically syncs applications
4. **Monitor**: Use ArgoCD UI to monitor application status

### Environment-Specific Configuration

Each environment has its own configuration:

- **dev**: Development environment with relaxed resource constraints
- **test**: Testing environment for QA
- **prod**: Production environment with strict resource limits
- **sbx**: Sandbox environment for experimentation

## Outputs

This layer does not produce Terraform outputs as it primarily contains Kubernetes manifests and Helmfile configurations. Application status and outputs are managed via ArgoCD and Kubernetes.

## Notes

### GitOps Workflow

1. **Make Changes**: Update application configurations in Git
2. **Commit and Push**: Push changes to Git repository
3. **ArgoCD Sync**: ArgoCD detects changes and syncs applications
4. **Monitor**: Use ArgoCD UI or CLI to monitor sync status

### External Secrets

Secrets are managed via External Secrets Operator, which retrieves secrets from AWS Secrets Manager and creates Kubernetes secrets. Applications reference these secrets via standard Kubernetes secret references.

### ArgoCD Application Sets

Application Sets provide automated application discovery and deployment. They can discover applications based on Git repository structure, Helm chart locations, or other criteria.

### Multi-Environment Management

Each environment has its own ArgoCD Application definitions and Helmfile values. This allows for environment-specific configurations while maintaining a common base configuration.

## References

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Helmfile Documentation](https://helmfile.readthedocs.io/)
- [External Secrets Operator](https://external-secrets.io/)
- [GitOps Principles](https://www.gitops.tech/)
- [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/configuration/overview/)
- [AWS Well-Architected Framework - Operational Excellence](https://docs.aws.amazon.com/wellarchitected/latest/operational-excellence-pillar/welcome.html)

