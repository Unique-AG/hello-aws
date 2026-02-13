# Cert-Manager Configuration for AWS

## Overview

This directory contains cert-manager ClusterIssuer configurations for different DNS providers.

## ClusterIssuers

### Route 53 DNS-01 (`cluster-issuer-route53.yaml`)

Uses Route 53 Private Hosted Zone for DNS-01 challenge validation with Let's Encrypt.

**Requirements:**
1. Route 53 Private Hosted Zone must exist (configured in infrastructure layer)
2. IAM role for cert-manager with Route 53 permissions
3. Service account annotation to use the IAM role (IRSA)

**IAM Role Permissions Required:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:GetChange",
        "route53:ChangeResourceRecordSets"
      ],
      "Resource": [
        "arn:aws:route53:::hostedzone/*",
        "arn:aws:route53:::change/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ListHostedZones",
        "route53:ListResourceRecordSets"
      ],
      "Resource": "*"
    }
  ]
}
```

**Service Account Annotation:**
The cert-manager service account must be annotated with the IAM role ARN:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cert-manager
  namespace: cert-manager
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/cert-manager-route53
```

### Azure DNS (`cluster-issuer.yaml`)

Legacy configuration for Azure DNS. Kept for reference but not used in AWS deployment.

## Usage

The helmfile automatically selects the appropriate ClusterIssuer based on the environment:
- **AWS EKS**: Uses `cluster-issuer-route53.yaml`
- **Azure AKS**: Uses `cluster-issuer.yaml` (legacy)

## Domain Configuration

The Route 53 ClusterIssuer is configured for:
- `sbx.aws.unique.dev` (Route 53 Private Hosted Zone domain)
- Wildcard support: `*.sbx.aws.unique.dev`

To add additional domains, update the `dnsZones` selector in `cluster-issuer-route53.yaml`.

