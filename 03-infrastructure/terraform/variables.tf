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

# Terraform State Configuration (for remote state access to bootstrap layer)
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

# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for the VPC (subnet layout assumes /19 or larger)"
  type        = string
  default     = "10.0.0.0/19"
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

variable "availability_zone_count" {
  description = "Number of Availability Zones to use (1-3)"
  type        = number
  default     = 3
  validation {
    condition     = var.availability_zone_count >= 1 && var.availability_zone_count <= 3
    error_message = "availability_zone_count must be between 1 and 3."
  }
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway instead of one per AZ. Not recommended for production (use check block for HA guard)."
  type        = bool
  default     = false
}

variable "secondary_cidr_enabled" {
  description = "Enable secondary CIDR block (100.64.0.0/20) for EKS pod networking"
  type        = bool
  default     = false
}

variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in the VPC"
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Enable DNS support in the VPC"
  type        = bool
  default     = true
}

# VPC Endpoints Configuration
variable "enable_s3_gateway_endpoint" {
  description = "Enable S3 Gateway Endpoint (free, required for ECR image layers)"
  type        = bool
  default     = true
}

variable "enable_kms_endpoint" {
  description = "Enable KMS Interface Endpoint"
  type        = bool
  default     = true
}

variable "enable_secrets_manager_endpoint" {
  description = "Enable Secrets Manager Interface Endpoint"
  type        = bool
  default     = true
}

variable "enable_ecr_endpoints" {
  description = "Enable ECR Interface Endpoints (API and Docker registry)"
  type        = bool
  default     = true
}

variable "enable_cloudwatch_endpoints" {
  description = "Enable CloudWatch Interface Endpoints (Logs and Metrics)"
  type        = bool
  default     = true
}

variable "enable_prometheus_endpoint" {
  description = "Enable Managed Prometheus Interface Endpoint"
  type        = bool
  default     = true
}

variable "enable_bedrock_endpoint" {
  description = "Enable Bedrock Interface Endpoint"
  type        = bool
  default     = true
}

variable "enable_sts_endpoint" {
  description = "Enable STS Interface Endpoint (required for IRSA token exchange)"
  type        = bool
  default     = true
}

variable "enable_ec2_endpoint" {
  description = "Enable EC2 Interface Endpoint (required for EC2 API access from management server)"
  type        = bool
  default     = true
}

variable "ssm_endpoints_enabled" {
  description = "Enable Systems Manager Interface Endpoints (required for Session Manager/bastion)"
  type        = bool
  default     = true
}

# KMS Configuration
variable "kms_deletion_window" {
  description = "Number of days to wait before deleting KMS keys (default: 30 days for production, override with 0 for immediate deletion in dev/sbx)"
  type        = number
  default     = 30 # Production default - override with 0 in dev/sbx for immediate deletion
}

variable "kms_enable_rotation" {
  description = "Enable automatic key rotation for KMS keys"
  type        = bool
  default     = true
}

# CloudWatch Configuration
variable "cloudwatch_log_retention_days" {
  description = "Number of days to retain CloudWatch logs (default: 30 days for production, override with 7 for fast teardown in dev/sbx)"
  type        = number
  default     = 30 # Production default - override in dev/sbx for fast teardown, prod can override with 90
}

# Managed Prometheus Configuration
variable "enable_managed_prometheus" {
  description = "Enable Amazon Managed Service for Prometheus (creates KMS key in infrastructure layer)"
  type        = bool
  default     = true
}

# Bastion and Management Server Configuration
variable "management_server_enabled" {
  description = "Enable EC2 management server (jump server)"
  type        = bool
  default     = true
}

variable "management_server_public_access" {
  description = "Enable public IP for management server (if false, use Session Manager only)"
  type        = bool
  default     = false
}

variable "management_server_instance_type" {
  description = "EC2 instance type for management server"
  type        = string
  default     = "t3.micro"
}

variable "management_server_ami" {
  description = "AMI ID for management server. Use a pre-baked golden AMI with tools installed. If empty, uses latest Amazon Linux 2023 base."
  type        = string
  default     = ""
}

variable "management_server_disk_size" {
  description = "Root disk size in GB for management server"
  type        = number
  default     = 20
}

variable "management_server_monitoring" {
  description = "Enable detailed CloudWatch monitoring for management server"
  type        = bool
  default     = true
}

# Monitoring and Alerting Configuration
variable "alert_email_endpoints" {
  description = "List of email addresses to receive infrastructure alerts via SNS"
  type        = list(string)
  default     = []
}

# GitHub Runners Configuration
variable "github_runners_enabled" {
  description = "Enable GitHub Actions self-hosted runners infrastructure"
  type        = bool
  default     = false
}

# Route 53 Private Hosted Zone Configuration
variable "route53_private_zone_domain" {
  description = "Domain name of the Route 53 Private Hosted Zone shared from landing zone (e.g., sbx.aws.unique.dev)"
  type        = string
  default     = null
}

variable "route53_private_zone_id" {
  description = "Zone ID of the Route 53 Private Hosted Zone shared from landing zone (e.g., Z061686132DMF010M5XAW). Required for VPC association."
  type        = string
  default     = null
}
