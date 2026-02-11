#######################################
# Naming Module
#######################################
#
# Centralized naming and tagging for all AWS resources.
# Implements HashiCorp best practices with AWS-specific
# length constraints.
#
# DRIFT PREVENTION:
# - Pass aws_account_id and aws_region explicitly for deterministic plans
#######################################

#######################################
# Data Sources (fallback only)
#######################################

data "aws_caller_identity" "current" {
  count = var.aws_account_id == null ? 1 : 0
}

data "aws_region" "current" {
  count = var.aws_region == null ? 1 : 0
}

#######################################
# Local Computations
#######################################

locals {
  delimiter = "-"

  # Deterministic AWS context
  account_id = coalesce(
    var.aws_account_id,
    try(data.aws_caller_identity.current[0].account_id, "000000000000")
  )

  region = coalesce(
    var.aws_region,
    try(data.aws_region.current[0].name, "eu-central-2")
  )

  # Environment short codes
  env_short = {
    prod = "p"
    stag = "s"
    dev  = "d"
    sbx  = "x"
  }

  # Region short codes (common AWS regions)
  region_short = {
    "us-east-1"      = "use1"
    "us-east-2"      = "use2"
    "us-west-1"      = "usw1"
    "us-west-2"      = "usw2"
    "eu-west-1"      = "euw1"
    "eu-west-2"      = "euw2"
    "eu-west-3"      = "euw3"
    "eu-central-1"   = "euc1"
    "eu-central-2"   = "euc2"
    "ap-southeast-1"  = "apse1"
    "ap-southeast-2" = "apse2"
    "ap-northeast-1" = "apne1"
    "ap-northeast-2" = "apne2"
    "ca-central-1"   = "cac1"
    "sa-east-1"      = "sae1"
  }

  # Fallback: generate short code from region name if not in map
  region_code = try(
    local.region_short[local.region],
    replace(replace(replace(local.region, "-", ""), "north", "n"), "south", "s")
  )

  # Base name parts: df-unique-sbx-euc2
  base_parts = compact([
    var.org_moniker,
    var.product,
    var.environment,
    local.region_code
  ])

  # Short name parts: df-unique-x-euc2
  short_parts = compact([
    var.org_moniker,
    var.product,
    local.env_short[var.environment],
    local.region_code
  ])

  # Full ID: df-unique-sbx-euc2
  id = join(local.delimiter, local.base_parts)

  # Short ID: df-unique-x-euc2
  id_short = join(local.delimiter, local.short_parts)

  #─────────────────────────────────────
  # Resource-Specific Names (with resource monikers)
  #─────────────────────────────────────

  # S3: 63 chars max, lowercase only, globally unique
  # Format: s3-{id_short}
  s3_bucket_prefix = lower(replace("s3-${local.id_short}", "_", "-"))

  # DynamoDB: 255 chars max
  # Format: dynamodb-{id}
  dynamodb_table_prefix = "dynamodb-${local.id}"

  # KMS: 256 chars max for alias
  # Format: kms-{id}
  kms_alias_prefix = "kms-${local.id}"

  # IAM Role: 64 chars max
  # Format: iam-{id}
  iam_role_prefix = substr("iam-${local.id}", 0, 50)

  # IAM Policy: 128 chars max
  # Format: iam-{id}
  iam_policy_prefix = substr("iam-${local.id}", 0, 100)

  # EKS: 100 chars max
  # Format: eks-{id}
  eks_cluster_name = substr("eks-${local.id}", 0, 100)

  # RDS: 63 chars max, alphanumeric + hyphen
  # Format: rds-{id}
  rds_identifier = substr(replace("rds-${local.id}", "_", "-"), 0, 63)

  # ElastiCache: 50 chars max
  # Format: elasticache-{id_short}
  elasticache_cluster_id = substr("elasticache-${local.id_short}", 0, 50)

  # ALB/NLB: 32 chars max
  # Format: alb-{id_short} or nlb-{id_short}
  lb_name = substr("alb-${local.id_short}", 0, 32)

  # Target Group: 32 chars max
  # Format: tg-{id_short}
  tg_name_prefix = substr("tg-${local.id_short}", 0, 28)

  # Lambda: 64 chars max
  # Format: lambda-{id}
  lambda_prefix = substr(replace("lambda-${local.id}", "-", "_"), 0, 50)

  # Security Group: 255 chars max
  # Format: sg-{id}
  sg_name_prefix = "sg-${local.id}"

  # CloudWatch Log Group: 512 chars max
  # Format: /{org_moniker}/{product}/{environment}
  # Note: Layer is tracked via tags, not in the log group path
  log_group_prefix = "/${var.org_moniker}/${var.product}/${var.environment}"

  #─────────────────────────────────────
  # Tags
  #─────────────────────────────────────

  # Required tags (always present)
  required_tags = {
    "org:Name"              = var.org
    "product:Id"            = var.product
    "product:Environment"   = var.environment
    "layer:Name"            = var.layer
    "governance:SemanticVersion" = var.semantic_version
    "automation:ManagedBy"  = "terraform"
    "automation:Pipeline"   = var.pipeline
    "cost:CostCenter"       = "product-${var.product}"
    "cost:Project"          = var.product
  }

  # Optional tags (only included when the variable is set)
  optional_tags = merge(
    var.org_domain != null ? { "org:Domain" = var.org_domain } : {},
    var.data_residency != null ? { "org:DataResidency" = var.data_residency } : {},
  )

  default_tags = merge(local.required_tags, local.optional_tags)
  tags         = local.default_tags
}

