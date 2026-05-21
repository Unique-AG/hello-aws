variable "subscription_id" {
  description = "Azure workload subscription ID"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "switzerlandnorth"
}

variable "environment" {
  description = "Environment name (prod, dev)"
  type        = string
}

variable "org" {
  description = "Organization identifier"
  type        = string
  default     = "hello-aws"
}

variable "product" {
  description = "Product identifier"
  type        = string
  default     = "unique"
}

variable "resource_group_name" {
  description = "Resource group name from core layer (hand-entered cross-layer reference)"
  type        = string
}

variable "foundry_sku" {
  description = "SKU for the Azure AI Foundry account"
  type        = string
  default     = "S0"
}

variable "gpt4o_model_version" {
  description = "GPT-4o model version to deploy (avoid retired 2024-08-06)"
  type        = string
  default     = "2024-11-20"
}

variable "gpt4o_capacity" {
  description = "TPM capacity in thousands (e.g. 30 = 30K TPM)"
  type        = number
  default     = 30
}
