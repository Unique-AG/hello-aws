# 02-governance Layer

## Overview

The governance layer implements account-level governance controls including cost management, compliance monitoring, and IAM policies. This layer provides the foundation for operational governance and cost optimization across the workload account.

## Design Rationale

### Account-Level Governance

The governance layer focuses on **account-specific governance controls** that complement organization-level policies. This design provides:

- **Cost Visibility**: Budget alerts and cost tracking at the account level
- **Compliance Monitoring**: Account-specific Config rules (when Config is enabled at org level)
- **IAM Governance**: Account-specific IAM roles and policies for governance operations
- **Flexibility**: Can be customized per account while maintaining consistency

### Separation of Concerns

Governance is separated from infrastructure to:

- **Enable Independent Updates**: Governance policies can be updated without affecting infrastructure
- **Clear Ownership**: Governance team can manage this layer independently
- **Compliance Tracking**: Clear separation for audit and compliance purposes

### Budget Management

AWS Budgets provides proactive cost management:

- **Monthly Budgets**: Track spending against monthly limits
- **Multi-Threshold Alerts**: Notifications at 80% and 100% of budget
- **Forecast Alerts**: Early warning when spending is projected to exceed budget
- **Email Notifications**: Direct alerts to stakeholders

### Config Rules (Optional)

Account-specific Config rules can be enabled when AWS Config is enabled at the organization level. These rules enforce:

- **Tagging Compliance**: Required tags on resources
- **Security Standards**: Account-specific security requirements
- **Resource Configuration**: Compliance with organizational standards

## Resources

### AWS Budgets

- **Monthly Cost Budget**: Tracks monthly spending
  - Configurable budget amount per environment
  - Email notifications at 80% and 100% thresholds
  - Forecast-based alerts for proactive management

### AWS Config Rules (Optional)

- **Required Tags Rule**: Ensures resources have required tags
  - Enforces organizational tagging standards
  - Scoped to specific resource types (EC2, RDS, S3, EKS)
  - Configurable tag requirements

### IAM Roles and Policies

- **Budget Administrator Role** (optional): For budget management operations
- **Security Auditor Role** (optional): For security review operations
- **Compliance Reviewer Role** (optional): For compliance verification

## Security Principles

### Least Privilege

- IAM roles follow least privilege principle
- Policies scoped to specific governance operations
- No wildcard permissions in governance policies

### Audit and Compliance

- Budget alerts provide cost visibility
- Config rules (when enabled) provide compliance monitoring
- All resources tagged for governance tracking

### Access Control

- IAM roles restricted to account-level operations
- No cross-account access from governance layer
- Conditional access based on region and resource type

## Well-Architected Framework

### Operational Excellence

- **Cost Visibility**: Budget alerts enable proactive cost management
- **Compliance Monitoring**: Config rules (when enabled) provide continuous compliance checking
- **Automation**: Budgets and Config rules are automated and require minimal maintenance

### Security

- **Least Privilege**: IAM roles follow least privilege principle
- **Compliance**: Config rules enforce security and compliance standards
- **Tagging**: Resources tagged for governance and compliance tracking

### Cost Optimization

- **Budget Management**: Proactive cost tracking and alerts
- **Cost Visibility**: Clear visibility into spending patterns
- **Threshold Alerts**: Early warning system for cost overruns

### Reliability

- **Automated Monitoring**: Budgets and Config rules run automatically
- **Alerting**: Multi-threshold alerts ensure timely notifications
- **Compliance**: Continuous compliance monitoring via Config rules

## Deployment

### Prerequisites

1. Bootstrap layer must be deployed first
2. `common.auto.tfvars` configured at repository root
3. Environment-specific configuration in `environments/{env}/00-config.auto.tfvars`

### Configuration

Configure budget settings in environment-specific configuration:

```hcl
budget_amount = 1000  # Monthly budget in USD
budget_contact_emails = ["admin@example.com"]
```

### Deployment Steps

```bash
./scripts/deploy.sh governance <environment>
```

**Environments**: `dev`, `test`, `prod`, `sbx`

**Options**:
- `--auto-approve`: Skip interactive confirmation
- `--skip-plan`: Skip the plan step and apply directly

### Post-Deployment

After deployment, verify:

1. Budget is created and active in AWS Budgets console
2. Email notifications are configured correctly
3. Config rules (if enabled) are active and compliant

## Outputs

- `budget_id`: ID of the monthly budget
- `budget_arn`: ARN of the monthly budget
- `config_rules` (if enabled): List of Config rule ARNs

## Notes

### AWS Config Service

The AWS Config service itself should be enabled at the **organization/landing zone level**, not in workload accounts. This layer provides account-specific Config rules that work with the organization-level Config service.

### Budget Configuration

Budgets are configured per environment. Production environments typically have higher budgets than development or sandbox environments. Budget amounts should be reviewed and updated regularly based on actual spending patterns.

## References

- [AWS Budgets Documentation](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html)
- [AWS Config Rules](https://docs.aws.amazon.com/config/latest/developerguide/evaluate-config_develop-rules.html)
- [AWS Well-Architected Framework - Cost Optimization](https://docs.aws.amazon.com/wellarchitected/latest/cost-optimization-pillar/welcome.html)
- [AWS Well-Architected Framework - Operational Excellence](https://docs.aws.amazon.com/wellarchitected/latest/operational-excellence-pillar/welcome.html)

