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

# Naming module variables
variable "org" {
  description = "Organization identifier"
  type        = string
  default     = "unique"
}

variable "org_moniker" {
  description = "Organization moniker (short abbreviation)"
  type        = string
  default     = "uq"
}

variable "client" {
  description = "Client identifier"
  type        = string
  default     = "acme"
}

variable "client_name" {
  description = "Client full name (for display/tagging purposes)"
  type        = string
  default     = "Unique Dog Food AG"
}

variable "environment" {
  description = "Environment name (prod, stag, dev, sbx)"
  type        = string
}

# Governance tracking variables
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

variable "github_actions_role_name" {
  description = "IAM role name for GitHub Actions OIDC"
  type        = string
  default     = "github-actions-terraform"
}

# Retention Configuration
variable "kms_deletion_window" {
  description = "Number of days to wait before deleting KMS keys (default: 30 days for production, override with 0 for immediate deletion in dev/sbx)"
  type        = number
  default     = 30 # Production default - override with 0 in dev/sbx for immediate deletion
}

variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs (default: 30 days for production, override with 7 for fast teardown in dev/sbx)"
  type        = number
  default     = 30 # Production default - override in dev/sbx for fast teardown
}
