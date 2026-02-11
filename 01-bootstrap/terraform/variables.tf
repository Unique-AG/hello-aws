variable "aws_region" {
  description = "The AWS region where resources will be created"
  type        = string
  default     = "eu-central-2"
}

variable "aws_account_id" {
  description = "AWS account ID (for deterministic naming, recommended for CI/CD)"
  type        = string
  default     = null
}

variable "org" {
  description = "Organization identifier"
  type        = string
}

variable "org_moniker" {
  description = "Organization moniker (short abbreviation)"
  type        = string
}

variable "product" {
  description = "Product identifier (for display and tags)"
  type        = string
}

variable "product_moniker" {
  description = "Product moniker for resource names (shortened version of product)"
  type        = string
}

variable "environment" {
  description = "Environment name (prod, stag, dev, sbx)"
  type        = string
}

variable "org_domain" {
  description = "Organization domain for tags (e.g., example.com). Omitted from tags if null."
  type        = string
  default     = null
}

variable "data_residency" {
  description = "Data residency region for tags (e.g., switzerland, eu). Omitted from tags if null."
  type        = string
  default     = null
}

variable "pipeline" {
  description = "CI/CD pipeline identifier for tags"
  type        = string
  default     = "github-actions"
}

variable "semantic_version" {
  description = "Semantic version (e.g., 1.0.0). Set by CI/CD"
  type        = string
  default     = "0.0.0"
}

variable "enable_versioning" {
  description = "Enable versioning on the S3 bucket"
  type        = bool
  default     = true
}

variable "enable_server_side_encryption" {
  description = "Enable server-side encryption on the S3 bucket"
  type        = bool
  default     = true
}

variable "enable_public_access_block" {
  description = "Enable S3 public access block"
  type        = bool
  default     = true
}

variable "use_oidc" {
  description = "Whether to use OIDC for authentication (for CI/CD)"
  type        = bool
  default     = false
}

variable "github_repository" {
  description = "GitHub repository in format 'owner/repo' for OIDC trust relationship"
  type        = string
  default     = ""
}

variable "kms_deletion_window" {
  description = "Number of days to wait before deleting KMS keys (default: 30 days for production, override with 0 for immediate deletion in dev/sbx)"
  type        = number
  default     = 30
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs (default: 30 days for production, override with 7 for fast teardown in dev/sbx)"
  type        = number
  default     = 30
}
