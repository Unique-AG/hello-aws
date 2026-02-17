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

# Terraform State Configuration (for remote state access)
# These are optional - if not provided, will be computed from naming module (same as bootstrap layer)
variable "terraform_state_bucket" {
  description = "S3 bucket name for Terraform state (from bootstrap layer). If not provided, computed from naming module."
  type        = string
  default     = null
}

variable "terraform_state_kms_key_id" {
  description = "KMS key ID/ARN for Terraform state encryption (from bootstrap layer). If not provided, computed from naming module."
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

variable "product" {
  description = "Product identifier (for display and tags)"
  type        = string
}

variable "product_moniker" {
  description = "Product moniker for resource names (shortened version of product)"
  type        = string
}

variable "client_name" {
  description = "Client full name (legacy, kept for backward compatibility with tfvars)"
  type        = string
  default     = ""
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

# EKS Cluster Configuration
variable "eks_cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.28"
}

variable "eks_ebs_csi_driver_version" {
  description = "Version of the EBS CSI driver addon"
  type        = string
  default     = null # Uses latest compatible version if null
}

variable "eks_endpoint_public_access" {
  description = "Enable public access to EKS cluster endpoint (default: false for security)"
  type        = bool
  default     = false
}

variable "eks_endpoint_private_access" {
  description = "Enable private access to EKS cluster endpoint"
  type        = bool
  default     = true
}

variable "eks_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks allowed to access EKS cluster endpoint (public access). Should be empty list if endpoint_public_access is false."
  type        = list(string)
  default     = []
}

variable "eks_enabled_cluster_log_types" {
  description = "List of control plane logging types to enable"
  type        = list(string)
  default = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]
}

variable "eks_cluster_log_retention_days" {
  description = "Number of days to retain EKS cluster logs in CloudWatch"
  type        = number
  default     = 7
}

# EKS Node Group Configuration
variable "eks_node_groups" {
  description = "Map of EKS node group configurations. Keys are pool names (e.g., steady, rapid)."
  type = map(object({
    instance_types  = optional(list(string), ["m6i.large"])
    capacity_type   = optional(string, "ON_DEMAND")
    disk_size       = optional(number, 100)
    desired_size    = optional(number, 0)
    min_size        = optional(number, 0)
    max_size        = optional(number, 3)
    max_unavailable = optional(number, 1)
    labels = optional(object({
      lifecycle   = string
      scalability = string
    }), { lifecycle = "ephemeral", scalability = "rapid" })
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [
      { key = "scalability", value = "rapid", effect = "NO_SCHEDULE" },
      { key = "lifecycle", value = "ephemeral", effect = "NO_SCHEDULE" }
    ])
  }))
}

# ECR Repository Configuration
variable "ecr_repositories" {
  description = "List of ECR repositories to create"
  type = list(object({
    name                 = string
    image_tag_mutability = string
    scan_on_push         = bool
    lifecycle_policy     = optional(string)
  }))
  default = []
}

variable "ecr_lifecycle_policy" {
  description = "Default lifecycle policy for ECR repositories (JSON string)"
  type        = string
  default     = null
}

# ECR Enhanced Scanning Configuration
variable "ecr_enhanced_scanning_enabled" {
  description = "Enable enhanced scanning for continuous vulnerability detection (recommended for production)"
  type        = bool
  default     = true
}

variable "ecr_scanning_rules" {
  description = "List of scanning rules for ECR registry scanning configuration"
  type = list(object({
    scan_frequency = string # SCAN_ON_PUSH, CONTINUOUS_SCAN, or MANUAL
    repository_filters = list(object({
      filter      = string
      filter_type = string # WILDCARD
    }))
  }))
  default = [
    {
      scan_frequency = "CONTINUOUS_SCAN"
      repository_filters = [
        {
          filter      = "*"
          filter_type = "WILDCARD"
        }
      ]
    }
  ]
}

# ECR Pull Through Cache Configuration
variable "ecr_pull_through_cache_upstream_registries" {
  description = "List of upstream registry prefixes to cache (e.g., ['docker.io', 'public.ecr.aws', 'uniqueapp.azurecr.io'])"
  type        = list(string)
  default     = []
}

variable "ecr_pull_through_cache_upstream_urls" {
  description = "Map of registry prefix to upstream registry URL for pull-through cache"
  type        = map(string)
  default = {
    "docker.io"      = "registry-1.docker.io"
    "public.ecr.aws" = "public.ecr.aws"
    "quay.io"        = "quay.io"
    "gcr.io"         = "gcr.io"
    "k8s.gcr.io"     = "k8s.gcr.io"
    "ghcr.io"        = "ghcr.io"
  }
  # Note: ACR URLs are dynamically added via locals based on acr_registry_url variable
}

# VPC Endpoints Configuration
variable "enable_eks_endpoint" {
  description = "Enable EKS Interface Endpoint (required for internal-only EKS deployments)"
  type        = bool
  default     = true
}

# Route 53 DNS Configuration
# Route 53 configuration is managed in infrastructure layer
# EKS cluster endpoint DNS resolution is handled automatically by EKS-managed private hosted zone
# No manual Route 53 records are needed for kubectl access from within the VPC

# Azure Container Registry (ACR) Configuration
variable "acr_registry_url" {
  description = "Azure Container Registry URL (e.g., uniqueapp.azurecr.io)"
  type        = string
  default     = ""
}

variable "acr_username" {
  description = "Azure Container Registry username (access key username)"
  type        = string
  default     = ""
  ephemeral   = true
}

variable "acr_password" {
  description = "Azure Container Registry password (access key)"
  type        = string
  default     = ""
  ephemeral   = true
}


