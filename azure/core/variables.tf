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
