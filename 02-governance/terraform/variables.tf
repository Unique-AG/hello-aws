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

# Budget configuration
variable "budget_amount" {
  description = "Monthly budget amount"
  type        = number
  default     = 1000
}

variable "budget_currency" {
  description = "Currency for budget limit (e.g., USD, EUR, CHF)"
  type        = string
  default     = "USD"
}

variable "budget_contact_emails" {
  description = "List of email addresses for budget notifications"
  type        = list(string)
  default     = []
}
