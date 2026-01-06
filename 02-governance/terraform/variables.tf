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

# Budget configuration
variable "budget_amount" {
  description = "Monthly budget amount in USD"
  type        = number
  default     = 1000
}

variable "budget_contact_emails" {
  description = "List of email addresses for budget notifications"
  type        = list(string)
  default     = []
}

# AWS Config Rules configuration
# Note: AWS Config service should be enabled at the organization/landing zone level
variable "enable_config_rules" {
  description = "Enable account-specific AWS Config rules (requires Config to be enabled at org level)"
  type        = bool
  default     = false
}

variable "config_rules" {
  description = "List of Config rule configurations"
  type = list(object({
    name              = string
    source_identifier = string
    input_parameters  = optional(string)
    resource_types    = optional(list(string))
    description       = optional(string)
  }))
  default = []
}

