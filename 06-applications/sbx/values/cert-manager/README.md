# Cert-Manager Configuration for AWS

## Overview

This directory contains cert-manager ClusterIssuer configurations for DNS-01 challenge validation.

## ClusterIssuers

### Internal CA (`cluster-issuer-internal-ca.yaml`)

A self-signed root CA used to issue short-lived TLS certificates for in-cluster service-to-service traffic (e.g., Kong's internal ALB listener, where CloudFront VPC Origin terminates external TLS). Chain:

1. `selfsigned-issuer` (`ClusterIssuer`, self-signed) — issues the CA certificate
2. `internal-ca` (`Certificate` in namespace `unique`, `isCA: true`, ECDSA P-256) — the CA itself
3. `internal-ca-issuer` (`ClusterIssuer`, backed by `internal-ca-secret`) — issues leaf certs for workloads

Workloads reference `internal-ca-issuer` via `issuerRef` on their `Certificate` resources.

### Route 53 DNS-01 (`cluster-issuer-route53.yaml`)

Uses Route 53 for DNS-01 challenge validation with Let's Encrypt.

**Requirements:**
1. Route 53 hosted zone must exist (configured in infrastructure layer)
2. IAM role for cert-manager with Route 53 permissions
3. EKS Pod Identity association (configured in `05-compute/terraform/iam.tf`)

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

**Pod Identity:**
The cert-manager service account is bound to an IAM role via EKS Pod Identity
(not IRSA annotations). The association is managed by Terraform in `05-compute`.

## Domain Configuration

The Route 53 ClusterIssuer is configured for `<DNS_ZONE>` with wildcard support.
The hosted zone ID and DNS zone are set via `instance-config.yaml` placeholders
(`<AWS_HOSTED_ZONE_ID>`, `<DNS_ZONE>`).

To add additional domains, update the `dnsZones` selector in `cluster-issuer-route53.yaml`.
