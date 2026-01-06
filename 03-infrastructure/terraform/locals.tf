locals {
  # Layer name for state file organization
  layer_name = "infrastructure"

  # State file key - organized by layer name
  state_file_key = "${local.layer_name}/terraform.tfstate"

  # Terraform state bucket name (computed from naming module, same as bootstrap layer)
  # Format: s3-{id_short}-tfstate
  # This matches the bootstrap layer's bucket name generation
  terraform_state_bucket = "${module.naming.s3_bucket_prefix}-tfstate"

  # KMS key alias for Terraform state encryption (computed from naming module, same as bootstrap layer)
  # Format: alias/kms-{id}-tfstate
  terraform_state_kms_key_id = "alias/kms-${module.naming.id}-tfstate"

  # Availability zones (use 3 for high availability)
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 3)

  # Subnet CIDR allocation
  # Following AWS best practices: fewer, larger subnets
  # Using /20 subnets (4096 addresses each) for better IP space utilization
  # Allocation:
  # - Public: 0-2 (3 subnets) - for NAT Gateway, load balancers
  # - Private: 3-5 (3 subnets) - for workloads (EKS, compute, AI, monitoring)
  # - Isolated: 6-8 (3 subnets) - for databases (RDS, ElastiCache) - no internet access
  subnet_allocations = {
    public   = { start = 0, count = 3 }
    private  = { start = 3, count = 3 }
    isolated = { start = 6, count = 3 }
  }

  # Additional tags (merged with naming module tags)
  additional_tags = {
    "client:Name" = var.client_name
  }

  # Combined tags (naming module tags + additional tags)
  tags = merge(module.naming.tags, local.additional_tags)

  # Bootstrap layer outputs (from remote state)
  # Available for reference if needed in future
  bootstrap = {
    s3_bucket_name            = data.terraform_remote_state.bootstrap.outputs.s3_bucket_name
    kms_key_arn               = data.terraform_remote_state.bootstrap.outputs.kms_key_arn
    kms_key_alias             = data.terraform_remote_state.bootstrap.outputs.kms_key_alias
    cloudwatch_log_group_name = data.terraform_remote_state.bootstrap.outputs.cloudwatch_log_group_name
  }
}

