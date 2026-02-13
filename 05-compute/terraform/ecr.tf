#######################################
# ECR Repositories
#######################################
#
# Amazon Elastic Container Registry (ECR) repositories
# for storing container images.
#
# ECR is configured as a pull-through cache to cache
# images from upstream registries (Docker Hub, public ECR, etc.)
#######################################

resource "aws_ecr_repository" "main" {
  #checkov:skip=CKV_AWS_163: see docs/security-baseline.md
  #checkov:skip=CKV_AWS_51: see docs/security-baseline.md
  for_each = {
    for repo in var.ecr_repositories : repo.name => repo
  }

  name                 = "${module.naming.id}-${each.value.name}"
  image_tag_mutability = each.value.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = each.value.scan_on_push
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = local.infrastructure.kms_key_arn
  }

  tags = merge(local.tags, {
    Name = "${module.naming.id}-${each.value.name}"
  })
}

#######################################
# ECR Registry Scanning Configuration
#######################################
#
# Enhanced scanning provides continuous, automated scanning for
# both operating system and programming language package vulnerabilities.
# This is a registry-level setting that applies to all repositories.
#######################################

resource "aws_ecr_registry_scanning_configuration" "main" {
  scan_type = var.ecr_enhanced_scanning_enabled ? "ENHANCED" : "BASIC"

  dynamic "rule" {
    for_each = var.ecr_scanning_rules
    content {
      scan_frequency = rule.value.scan_frequency

      dynamic "repository_filter" {
        for_each = rule.value.repository_filters
        content {
          filter      = repository_filter.value.filter
          filter_type = repository_filter.value.filter_type
        }
      }
    }
  }
}

#######################################
# ECR Repository Creation Template
#######################################
#
# Repository creation templates define default settings for repositories
# created via pull-through cache. This ensures cached images are scanned
# and follow security best practices.
#
# Note: Repository creation templates are configured via AWS Console or CLI:
#   aws ecr put-registry-policy --policy-text file://policy.json
#
# The template should enable:
#   - Image scanning (enhanced scanning)
#   - KMS encryption
#   - Lifecycle policies (optional)
#
# See README.md for manual configuration steps.
#######################################

#######################################
# ECR Image Scanning EventBridge Integration
#######################################
#
# EventBridge rules to capture ECR image scanning findings
# and send them to Security Hub or other security services.
#######################################

# EventBridge rule for ECR image scan findings
resource "aws_cloudwatch_event_rule" "ecr_image_scan" {
  name        = "${module.naming.id}-ecr-image-scan"
  description = "Capture ECR image scanning findings"

  event_pattern = jsonencode({
    source      = ["aws.ecr"]
    detail-type = ["ECR Image Scan"]
    detail = {
      "scan-status" = ["COMPLETE"]
      "finding-severity-counts" = {
        CRITICAL = [{ "exists" : true }]
        HIGH     = [{ "exists" : true }]
      }
    }
  })

  tags = merge(local.tags, {
    Name = "${module.naming.id}-ecr-image-scan-rule"
  })
}

# EventBridge rule target - SNS topic for notifications (optional)
# Uncomment and configure if you want SNS notifications for scan findings
# resource "aws_sns_topic" "ecr_scan_findings" {
#   name = "${module.naming.id}-ecr-scan-findings"
#   kms_master_key_id = local.infrastructure.kms_key_id
#   tags = local.tags
# }
#
# resource "aws_cloudwatch_event_target" "ecr_scan_sns" {
#   rule      = aws_cloudwatch_event_rule.ecr_image_scan.name
#   target_id = "SendToSNS"
#   arn       = aws_sns_topic.ecr_scan_findings.arn
# }

# ECR Lifecycle Policy
resource "aws_ecr_lifecycle_policy" "main" {
  for_each = {
    for repo in var.ecr_repositories : repo.name => repo
    if repo.lifecycle_policy != null
  }

  repository = aws_ecr_repository.main[each.key].name

  policy = each.value.lifecycle_policy
}

# Default ECR Lifecycle Policy (if provided)
resource "aws_ecr_lifecycle_policy" "default" {
  for_each = {
    for repo in var.ecr_repositories : repo.name => repo
    if repo.lifecycle_policy == null && var.ecr_lifecycle_policy != null
  }

  repository = aws_ecr_repository.main[each.key].name

  policy = var.ecr_lifecycle_policy
}

#######################################
# ECR Pull Through Cache Rules
#######################################
#
# Pull-through cache rules allow ECR to cache images from
# upstream registries (Docker Hub, public ECR, Azure Container Registry, etc.)
# This reduces external registry dependencies and improves
# pull performance and reliability.
#
# Note: This is a registry-level configuration that applies
# to all repositories in the account.
#
# For authenticated registries (Docker Hub, ACR), credentials must be stored
# in AWS Secrets Manager with the pattern: ecr-pullthroughcache/<registry-url>
# Secret value: JSON with "username" and "password" fields
#######################################

# Secrets Manager secret for Azure Container Registry credentials
# Required for ECR pull-through cache to authenticate with ACR
resource "aws_secretsmanager_secret" "acr_credentials" {
  count = var.acr_registry_url != "" ? 1 : 0

  name        = "ecr-pullthroughcache/${var.acr_registry_url}"
  description = "Azure Container Registry credentials for ECR pull-through cache"
  kms_key_id  = local.infrastructure.kms_key_secrets_manager_arn

  tags = merge(local.tags, {
    Name = "${module.naming.id}-acr-credentials"
  })
}

resource "aws_secretsmanager_secret_version" "acr_credentials" {
  count = var.acr_registry_url != "" ? 1 : 0

  secret_id = aws_secretsmanager_secret.acr_credentials[0].id

  # Use write-only attribute to avoid storing secret in Terraform state
  secret_string_wo = jsonencode({
    username    = var.acr_username
    accessToken = var.acr_password
  })
  # Increment this when the secret value changes to trigger an update
  secret_string_wo_version = 2
}

# Resource policy to allow ECR to access the secret
resource "aws_secretsmanager_secret_policy" "acr_credentials" {
  count = var.acr_registry_url != "" ? 1 : 0

  secret_arn = aws_secretsmanager_secret.acr_credentials[0].arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowECRPullThroughCache"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/pullthroughcache.ecr.amazonaws.com/AWSServiceRoleForECRPullThroughCache" }
        Action    = "secretsmanager:GetSecretValue"
        Resource  = aws_secretsmanager_secret.acr_credentials[0].arn
      }
    ]
  })
}

# ECR Pull Through Cache Rules
# Exclude ACR-related rules if credentials are not configured to avoid update errors
locals {
  # Filter out ACR rules if credentials are not provided
  # AWS doesn't allow removing credentials from existing rules, so we skip them entirely
  # Use variable (known at plan time) instead of resource reference to avoid for_each unknown key errors
  acr_configured = var.acr_registry_url != ""
  # Filter registries: exclude ACR-related ones if ACR is not configured
  ecr_pull_through_cache_registries = local.acr_configured ? var.ecr_pull_through_cache_upstream_registries : [for reg in var.ecr_pull_through_cache_upstream_registries : reg if reg != var.acr_registry_url && reg != local.acr_alias]
}

resource "aws_ecr_pull_through_cache_rule" "main" {
  for_each = toset(local.ecr_pull_through_cache_registries)

  ecr_repository_prefix = each.value
  upstream_registry_url = local.ecr_pull_through_cache_upstream_urls[each.value]

  # For authenticated registries (ACR), provide the credential ARN
  # Support both the full ACR URL and the short alias (extracted from ACR URL)
  credential_arn = (each.value == var.acr_registry_url || each.value == local.acr_alias) && local.acr_configured ? aws_secretsmanager_secret.acr_credentials[0].arn : null

  depends_on = [aws_secretsmanager_secret_policy.acr_credentials]
}

