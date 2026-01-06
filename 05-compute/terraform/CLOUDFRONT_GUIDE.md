# CloudFront Setup Guide for AWS Landing Zone

## Overview

This guide describes the complete architecture and setup for Amazon CloudFront with your EKS cluster on Sandbox. The solution uses a **cross-account architecture** with **no Terraform state connection** between the connectivity and hello-aws accounts.

## Architecture

### Cross-Account Architecture

```
Account A: Connectivity/Infrastructure Account
├── CloudFront Distribution (one per environment)
├── WAF (centralized security)
└── Route 53 (optional)

Account B: hello-aws Account (Application Account)
├── EKS Cluster
├── ALB (created by AWS Load Balancer Controller)
└── Application Services
```

**Traffic Flow:**
```
Azure DNS (hello.sbx.aws.unique.dev)
    ↓ CNAME
CloudFront Distribution (connectivity account)
    ↓ HTTPS (public internet)
ALB DNS Name (hello-aws account)
    ↓
EKS Cluster (hello-aws account)
```

### Key Design Decisions

1. **One CloudFront Resource, One Distribution Per Environment**
   - Single Terraform resource definition (DRY principle)
   - One CloudFront distribution per environment (sbx, dev, test, prod)
   - Environment-specific configuration via variables

2. **Cross-Account Architecture**
   - Connectivity account: CloudFront, WAF, edge services
   - hello-aws account: EKS, ALB, applications
   - **No Terraform state connection** between accounts

3. **No VPC Required for CloudFront**
   - CloudFront is a global edge service (not VPC-based)
   - Connects to ALBs via DNS over public internet
   - No VPC peering or direct connectivity needed

4. **ALB Discovery via Naming Convention**
   - EKS cluster name known via naming convention
   - ALB discovery using AWS API (cross-account provider)
   - No dependency on Terraform remote state

## Naming Convention

### EKS Cluster Name Pattern

```
eks-<org-moniker>-<client>-<environment>-<region-short>
```

**Examples:**
- `eks-uq-dogfood-sbx-euc2` (Sandbox, eu-central-2)
- `eks-uq-dogfood-dev-euc2` (Dev, eu-central-2)
- `eks-uq-dogfood-prod-euc2` (Production, eu-central-2)

### Implementation

```hcl
# In connectivity layer
locals {
  eks_cluster_name = "eks-${var.org_moniker}-${var.client}-${var.environment}-${substr(var.aws_region, 0, 5)}"
}
```

## Directory Structure

### Connectivity Layer (External to hello-aws)

```
aws-connectivity/terraform/
├── providers.tf          # Cross-account provider configuration
├── data.tf               # ALB discovery (cross-account)
├── cloudfront.tf         # ONE centralized CloudFront resource
├── waf.tf                # WAF rules (optional)
├── variables.tf
├── outputs.tf
└── environments/
    ├── sbx/
    │   └── 00-config.auto.tfvars  # Creates ONE CloudFront Distribution (sbx)
    ├── dev/
    │   └── 00-config.auto.tfvars  # Creates ONE CloudFront Distribution (dev)
    ├── test/
    │   └── 00-config.auto.tfvars  # Creates ONE CloudFront Distribution (test)
    └── prod/
        └── 00-config.auto.tfvars  # Creates ONE CloudFront Distribution (prod)
```

## Complete Implementation

### Step 1: Cross-Account IAM Setup

#### In hello-aws Account

Create an IAM role that the connectivity account can assume:

```hcl
# In hello-aws account (or separate IAM module)
resource "aws_iam_role" "connectivity_read_only" {
  name = "connectivity-account-read-only-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::<connectivity-account-id>:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Custom policy for ALB discovery (more restrictive than ReadOnlyAccess)
resource "aws_iam_policy" "alb_discovery" {
  name        = "alb-discovery-policy"
  description = "Allow ALB discovery for CloudFront"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeTags",
          "elasticloadbalancing:DescribeTargetGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "alb_discovery" {
  role       = aws_iam_role.connectivity_read_only.name
  policy_arn = aws_iam_policy.alb_discovery.arn
}
```

### Step 2: Connectivity Layer Configuration

#### `providers.tf` - Cross-Account Provider

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Default provider: Connectivity account
provider "aws" {
  region = var.aws_region
  # Uses default credentials/role for connectivity account
}

# Provider for hello-aws account (cross-account)
provider "aws" {
  alias  = "hello_aws"
  region = var.aws_region

  assume_role {
    role_arn = var.hello_aws_assume_role_arn
  }
}
```

#### `data.tf` - ALB Discovery

```hcl
# EKS cluster name from naming convention
locals {
  eks_cluster_name = "eks-${var.org_moniker}-${var.client}-${var.environment}-${substr(var.aws_region, 0, 5)}"
}

# Discover ALBs in hello-aws account (cross-account)
data "aws_lbs" "eks_albs" {
  provider = aws.hello_aws
  
  tags = {
    "elbv2.k8s.aws/cluster" = local.eks_cluster_name
  }
}

# Get first ALB (or filter if multiple exist)
data "aws_lb" "eks_alb" {
  provider = aws.hello_aws
  arn      = length(data.aws_lbs.eks_albs.arns) > 0 ? data.aws_lbs.eks_albs.arns[0] : null
}

# Local for ALB DNS name
locals {
  alb_dns_name = data.aws_lb.eks_alb.dns_name
}
```

#### `cloudfront.tf` - CloudFront Distribution

```hcl
# ONE centralized CloudFront resource
# Creates ONE distribution per environment when applied

resource "aws_cloudfront_distribution" "landing_zone" {
  enabled         = true
  is_ipv6_enabled = var.cloudfront_ipv6_enabled
  comment         = "CloudFront for AWS Landing Zone - ${var.environment}"
  price_class     = var.cloudfront_price_class

  # Custom domain aliases
  aliases = var.cloudfront_aliases != null ? var.cloudfront_aliases : []

  # Origin: ALB from hello-aws account
  origin {
    domain_name = local.alb_dns_name
    origin_id   = "eks-alb-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_read_timeout    = 60
      origin_keepalive_timeout = 5
    }

    # Custom header for security (optional)
    dynamic "custom_header" {
      for_each = var.cloudfront_custom_header_value != null ? [1] : []
      content {
        name  = var.cloudfront_custom_header_name
        value = var.cloudfront_custom_header_value
      }
    }
  }

  # Default cache behavior (for API endpoints - minimal caching)
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "eks-alb-origin"

    forwarded_values {
      query_string = true
      headers      = ["*"]
      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
    compress               = true
  }

  # Cache behavior for static assets (optional)
  dynamic "ordered_cache_behavior" {
    for_each = var.cloudfront_static_path_pattern != null ? [1] : []
    content {
      path_pattern     = var.cloudfront_static_path_pattern
      allowed_methods  = ["GET", "HEAD", "OPTIONS"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = "eks-alb-origin"

      forwarded_values {
        query_string = false
        headers      = ["Origin", "Access-Control-Request-Headers", "Access-Control-Request-Method"]
        cookies {
          forward = "none"
        }
      }

      viewer_protocol_policy = "redirect-to-https"
      min_ttl                = var.cloudfront_static_min_ttl
      default_ttl            = var.cloudfront_static_default_ttl
      max_ttl                = var.cloudfront_static_max_ttl
      compress               = true
    }
  }

  # WAF Web ACL (optional)
  web_acl_id = var.cloudfront_waf_web_acl_id

  # SSL/TLS certificate (must be in us-east-1 for CloudFront)
  viewer_certificate {
    cloudfront_default_certificate = var.cloudfront_certificate_arn == null
    acm_certificate_arn            = var.cloudfront_certificate_arn
    ssl_support_method             = var.cloudfront_certificate_arn != null ? "sni-only" : null
    minimum_protocol_version       = var.cloudfront_certificate_arn != null ? "TLSv1.2_2021" : null
  }

  # Geo-restriction (optional)
  restrictions {
    geo_restriction {
      restriction_type = var.cloudfront_geo_restriction_type != null ? var.cloudfront_geo_restriction_type : "none"
      locations        = var.cloudfront_geo_restriction_locations
    }
  }

  # Logging configuration (optional)
  dynamic "logging_config" {
    for_each = var.cloudfront_logging_enabled ? [1] : []
    content {
      bucket          = aws_s3_bucket.cloudfront_logs[0].bucket_domain_name
      include_cookies = var.cloudfront_logging_include_cookies
      prefix          = var.cloudfront_logging_prefix
    }
  }

  tags = merge(var.tags, {
    Name        = "cloudfront-${var.environment}"
    Environment = var.environment
  })
}

# S3 bucket for CloudFront logs (if logging enabled)
resource "aws_s3_bucket" "cloudfront_logs" {
  count  = var.cloudfront_logging_enabled ? 1 : 0
  bucket = "${var.s3_bucket_prefix}-cloudfront-logs-${var.environment}"

  tags = merge(var.tags, {
    Name = "cloudfront-logs-${var.environment}"
  })
}

resource "aws_s3_bucket_versioning" "cloudfront_logs" {
  count  = var.cloudfront_logging_enabled ? 1 : 0
  bucket = aws_s3_bucket.cloudfront_logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudfront_logs" {
  count  = var.cloudfront_logging_enabled ? 1 : 0
  bucket = aws_s3_bucket.cloudfront_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudfront_logs" {
  count  = var.cloudfront_logging_enabled ? 1 : 0
  bucket = aws_s3_bucket.cloudfront_logs[0].id

  rule {
    id     = "delete-old-logs"
    status = "Enabled"
    expiration {
      days = var.cloudfront_log_retention_days
    }
  }
}

resource "aws_s3_bucket_policy" "cloudfront_logs" {
  count  = var.cloudfront_logging_enabled ? 1 : 0
  bucket = aws_s3_bucket.cloudfront_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontLogDelivery"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudfront_logs[0].arn}/*"
        Condition = {
          StringEquals = {
            "aws:SourceArn" = "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/${aws_cloudfront_distribution.landing_zone.id}"
          }
        }
      }
    ]
  })
}
```

#### `variables.tf` - Configuration Variables

```hcl
variable "environment" {
  description = "Environment name (sbx, dev, test, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-2"
}

# Cross-account configuration
variable "hello_aws_account_id" {
  description = "AWS account ID for hello-aws account"
  type        = string
}

variable "hello_aws_assume_role_arn" {
  description = "ARN of IAM role to assume in hello-aws account"
  type        = string
}

# Naming convention
variable "org_moniker" {
  description = "Organization moniker (e.g., 'uq')"
  type        = string
  default     = "uq"
}

variable "client" {
  description = "Client identifier (e.g., 'dogfood')"
  type        = string
}

# CloudFront configuration
variable "cloudfront_ipv6_enabled" {
  description = "Enable IPv6 for CloudFront distribution"
  type        = bool
  default     = true
}

variable "cloudfront_price_class" {
  description = "Price class for CloudFront (PriceClass_All, PriceClass_200, PriceClass_100)"
  type        = string
  default     = "PriceClass_100"
}

variable "cloudfront_aliases" {
  description = "List of custom domain aliases (CNAMEs)"
  type        = list(string)
  default     = null
}

variable "cloudfront_certificate_arn" {
  description = "ARN of ACM certificate for CloudFront (must be in us-east-1)"
  type        = string
  default     = null
}

variable "cloudfront_custom_header_name" {
  description = "Custom header name to validate requests from CloudFront"
  type        = string
  default     = "X-CloudFront-Secret"
}

variable "cloudfront_custom_header_value" {
  description = "Custom header value (should be a secret)"
  type        = string
  default     = null
  sensitive   = true
}

variable "cloudfront_waf_web_acl_id" {
  description = "ARN of AWS WAF Web ACL to associate with CloudFront"
  type        = string
  default     = null
}

variable "cloudfront_static_path_pattern" {
  description = "Path pattern for static assets cache behavior (e.g., '/static/*')"
  type        = string
  default     = null
}

variable "cloudfront_static_min_ttl" {
  description = "Minimum TTL for static assets (seconds)"
  type        = number
  default     = 86400
}

variable "cloudfront_static_default_ttl" {
  description = "Default TTL for static assets (seconds)"
  type        = number
  default     = 604800
}

variable "cloudfront_static_max_ttl" {
  description = "Maximum TTL for static assets (seconds)"
  type        = number
  default     = 31536000
}

variable "cloudfront_geo_restriction_type" {
  description = "Type of geo-restriction (none, whitelist, blacklist)"
  type        = string
  default     = null
}

variable "cloudfront_geo_restriction_locations" {
  description = "List of country codes for geo-restriction"
  type        = list(string)
  default     = []
}

variable "cloudfront_logging_enabled" {
  description = "Enable CloudFront access logging"
  type        = bool
  default     = true
}

variable "cloudfront_logging_include_cookies" {
  description = "Include cookies in CloudFront access logs"
  type        = bool
  default     = false
}

variable "cloudfront_logging_prefix" {
  description = "Prefix for CloudFront access logs in S3"
  type        = string
  default     = "cloudfront-logs"
}

variable "cloudfront_log_retention_days" {
  description = "Number of days to retain CloudFront access logs"
  type        = number
  default     = 90
}

variable "s3_bucket_prefix" {
  description = "Prefix for S3 bucket names"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
```

#### `outputs.tf` - Outputs

```hcl
output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.landing_zone.id
}

output "cloudfront_distribution_arn" {
  description = "ARN of the CloudFront distribution"
  value       = aws_cloudfront_distribution.landing_zone.arn
}

output "cloudfront_distribution_domain_name" {
  description = "Domain name of the CloudFront distribution (for Azure DNS CNAME)"
  value       = aws_cloudfront_distribution.landing_zone.domain_name
}

output "cloudfront_distribution_hosted_zone_id" {
  description = "Route 53 hosted zone ID for the CloudFront distribution"
  value       = aws_cloudfront_distribution.landing_zone.hosted_zone_id
}

output "eks_cluster_name" {
  description = "EKS cluster name (from naming convention)"
  value       = local.eks_cluster_name
}

output "alb_dns_name" {
  description = "ALB DNS name discovered from hello-aws account"
  value       = local.alb_dns_name
}
```

### Step 3: Environment Configuration

#### `environments/sbx/00-config.auto.tfvars`

```hcl
environment = "sbx"

# Cross-account configuration
hello_aws_account_id      = "123456789012"  # hello-aws account ID
hello_aws_assume_role_arn = "arn:aws:iam::123456789012:role/connectivity-account-read-only-role"

# Naming convention
org_moniker = "uq"
client      = "dogfood"
aws_region  = "eu-central-2"

# CloudFront Configuration
cloudfront_ipv6_enabled = true
cloudfront_price_class  = "PriceClass_100"  # US, Canada, Europe only (cheaper)

# Custom domain
cloudfront_aliases = ["hello.sbx.aws.unique.dev"]

# SSL Certificate (optional for sandbox)
# cloudfront_certificate_arn = "arn:aws:acm:us-east-1:<account-id>:certificate/<cert-id>"

# Security: Custom header (generate secret value)
# cloudfront_custom_header_name  = "X-CloudFront-Secret"
# cloudfront_custom_header_value = "<generate-secret-value>"

# WAF (optional for sandbox - cost savings)
# cloudfront_waf_web_acl_id = null

# Static assets caching (optional)
# cloudfront_static_path_pattern = "/static/*"

# Logging
cloudfront_logging_enabled        = true
cloudfront_logging_include_cookies = false
cloudfront_logging_prefix         = "cloudfront-logs"
cloudfront_log_retention_days     = 7  # Fast teardown for sandbox

# S3 bucket prefix
s3_bucket_prefix = "s3-uq-dogfood-sbx-euc2"
```

## Azure DNS Integration

### Update DNS Configuration

After CloudFront is created, update `00-unique.dev.yaml`:

```yaml
subzones:
  - name: aws
    records_cname:
      - name: "hello.sbx"
        ttl: 300
        record: "d<cloudfront-distribution-id>.cloudfront.net."
        # Replace <cloudfront-distribution-id> with actual CloudFront domain
        # Example: d1234567890abc.cloudfront.net.
```

**Note:** The trailing dot (`.`) is important - it indicates a fully qualified domain name.

## Alternative: Manual ALB DNS Name

If cross-account IAM setup is not desired, use manual configuration:

```hcl
# variables.tf
variable "alb_dns_name" {
  description = "ALB DNS name (manual configuration, no cross-account discovery)"
  type        = string
}

# data.tf - Skip ALB discovery, use variable directly
locals {
  alb_dns_name = var.alb_dns_name
}

# environments/sbx/00-config.auto.tfvars
alb_dns_name = "k8s-example-ingress-abc123.eu-central-2.elb.amazonaws.com"
```

## Benefits of This Architecture

### 1. Centralized Security
- Single WAF policy per environment
- Consistent security rules
- Centralized DDoS protection

### 2. Cost Efficiency
- One CloudFront distribution per environment (not per service)
- Shared edge caching infrastructure
- Environment-specific price classes

### 3. Operational Simplicity
- Single point of management per environment
- Centralized logging and monitoring
- Easier troubleshooting

### 4. Flexibility
- Multiple origins (ALBs) can be added
- Path-based or host-based routing
- Easy to scale

### 5. Account Separation
- Connectivity concerns separate from application concerns
- Independent deployment cycles
- Clear ownership boundaries

## Security Considerations

### 1. ALB Security Group
- Restrict ALB to only accept traffic from CloudFront
- Use custom header validation
- Or restrict to CloudFront IP ranges (requires regular updates)

### 2. CloudFront Custom Header
- Add secret header that ALB validates
- Rotate periodically for security

### 3. WAF Integration
- Add AWS WAF for additional protection
- Centralized rule management

### 4. HTTPS Only
- CloudFront redirects HTTP to HTTPS
- Use ACM certificate for custom domains

## Deployment Steps

### 1. Create IAM Role in hello-aws Account

```bash
# In hello-aws account
cd hello-aws/terraform
terraform apply  # Creates connectivity-read-only-role
```

### 2. Deploy CloudFront in Connectivity Account

```bash
# In connectivity account
cd aws-connectivity/terraform
terraform init
terraform plan -var-file=environments/sbx/00-config.auto.tfvars
terraform apply -var-file=environments/sbx/00-config.auto.tfvars
```

### 3. Update Azure DNS

```bash
# Get CloudFront domain name
terraform output cloudfront_distribution_domain_name

# Update 00-unique.dev.yaml with CloudFront domain
# Deploy Azure DNS changes
```

## Troubleshooting

### ALB Not Found

```bash
# List ALBs in hello-aws account
aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(LoadBalancerName, 'k8s')].{Name:LoadBalancerName,DNS:DNSName}" \
  --output table

# Check ALB tags
aws elbv2 describe-tags --resource-arns <alb-arn> \
  --query 'TagDescriptions[0].Tags[?Key==`elbv2.k8s.aws/cluster`]'
```

### Verify Cluster Name

```bash
# List EKS clusters
aws eks list-clusters --query 'clusters[]' --output table

# Cluster name follows: eks-<org-moniker>-<client>-<env>-<region-short>
```

### Test DNS Resolution

```bash
# Test Azure DNS
dig hello.sbx.aws.unique.dev

# Should resolve to CloudFront domain
# Which resolves to CloudFront edge IPs
```

## Summary

✅ **Architecture:**
- Cross-account: Connectivity account (CloudFront) → hello-aws account (ALB/EKS)
- One CloudFront resource, one distribution per environment
- No Terraform state connection
- Cluster name from naming convention

✅ **CloudFront:**
- Global edge service (no VPC required)
- Connects to ALB via DNS over internet
- Maps directly to ALB DNS names

✅ **ALB Discovery:**
- Cross-account AWS provider with assume role
- Cluster name: `eks-<org-moniker>-<client>-<env>-<region-short>`
- Alternative: Manual ALB DNS name configuration

✅ **Integration:**
- Azure DNS: CNAME record → CloudFront domain
- CloudFront: Origin → ALB DNS name
- Multiple services can use same CloudFront distribution

