#######################################
# Core Identifiers
#######################################

variable "org" {
  description = "Organization identifier (for display and tags)"
  type        = string
  default     = "dogfood"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$|^[a-z]$", var.org)) && !can(regex("--", var.org))
    error_message = "org must be lowercase alphanumeric with hyphens, start with letter, end with alphanumeric, no consecutive hyphens"
  }
}

variable "org_moniker" {
  description = "Organization moniker for resource names (shortened version of org)"
  type        = string
  default     = "df"

  validation {
    condition     = length(var.org_moniker) >= 2 && length(var.org_moniker) <= 10 && can(regex("^[a-z][a-z0-9-]*[a-z0-9]$|^[a-z]+$", var.org_moniker)) && !can(regex("--", var.org_moniker))
    error_message = "org_moniker must be 2-10 characters, lowercase alphanumeric with hyphens, start with letter, end with alphanumeric, no consecutive hyphens"
  }
}

variable "product" {
  description = "Product identifier (for display and tags)"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$|^[a-z]$", var.product)) && !can(regex("--", var.product))
    error_message = "product must be lowercase alphanumeric with hyphens, start with letter, end with alphanumeric, no consecutive hyphens"
  }
}

variable "product_moniker" {
  description = "Product moniker for resource names (shortened version of product)"
  type        = string

  validation {
    condition     = length(var.product_moniker) >= 2 && length(var.product_moniker) <= 10 && can(regex("^[a-z][a-z0-9-]*[a-z0-9]$|^[a-z]+$", var.product_moniker)) && !can(regex("--", var.product_moniker))
    error_message = "product_moniker must be 2-10 characters, lowercase alphanumeric with hyphens, start with letter, end with alphanumeric, no consecutive hyphens"
  }
}

variable "layer" {
  description = "Layer identifier (e.g., bootstrap, governance, infrastructure)"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$|^[a-z]$", var.layer)) && !can(regex("--", var.layer))
    error_message = "layer must be lowercase alphanumeric with hyphens, start with letter, end with alphanumeric, no consecutive hyphens"
  }
}

variable "environment" {
  description = "Environment (prod, stag, dev, sbx)"
  type        = string

  validation {
    condition     = contains(["prod", "stag", "dev", "sbx"], var.environment)
    error_message = "Environment must be one of: prod, stag, dev, sbx"
  }
}

#######################################
# AWS Context (Drift Prevention)
#######################################

variable "aws_account_id" {
  description = "AWS Account ID. Pass explicitly for deterministic plans."
  type        = string
  default     = null

  validation {
    condition     = var.aws_account_id == null || can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be exactly 12 digits"
  }
}

variable "aws_region" {
  description = "AWS Region. Pass explicitly for deterministic plans."
  type        = string
  default     = null

  validation {
    condition = var.aws_region == null || can(regex(
      "^(us|eu|ap|sa|ca|af|me|il|cn)-(central|north|south|east|west|northeast|northwest|southeast|southwest|gov|iso|isob)-[0-9]+$",
      var.aws_region
    ))
    error_message = "aws_region must be a valid AWS region format (e.g., us-east-1, eu-central-2, us-gov-east-1)"
  }
}

#######################################
# Tag Configuration
#######################################

variable "org_domain" {
  description = "Organization domain for tags (e.g., dogfood.ch). Omitted from tags if null."
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

#######################################
# Governance Tracking
#######################################

variable "semantic_version" {
  description = "Semantic version (e.g., 1.0.0). Set by CI/CD"
  type        = string
  default     = "0.0.0"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+(-[a-zA-Z0-9-]+(\\.[a-zA-Z0-9-]+)*)?(\\+[a-zA-Z0-9-]+(\\.[a-zA-Z0-9-]+)*)?$", var.semantic_version))
    error_message = "semantic_version must follow semantic versioning format (e.g., 1.0.0, 1.0.0-alpha, 1.0.0-alpha.1, 1.0.0+build.1)"
  }
}


