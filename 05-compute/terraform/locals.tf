locals {
  # Layer name for state file organization
  layer_name = "compute"

  # State file key - organized by layer name
  state_file_key = "${local.layer_name}/terraform.tfstate"

  # Terraform state bucket name (computed from naming module, same as bootstrap layer)
  # Format: s3-{id_short}-tfstate
  terraform_state_bucket = "${module.naming.s3_bucket_prefix}-tfstate"

  # KMS key alias for Terraform state encryption (computed from naming module, same as bootstrap layer)
  # Format: alias/kms-{id}-tfstate
  terraform_state_kms_key_id = "alias/kms-${module.naming.id}-tfstate"

  # Additional tags (merged with naming module tags)
  additional_tags = {
    "client:Name" = var.client_name
  }

  # Combined tags (naming module tags + additional tags)
  tags = merge(module.naming.tags, local.additional_tags)

  # Infrastructure layer outputs (from remote state)
  infrastructure = {
    vpc_id                                   = data.terraform_remote_state.infrastructure.outputs.vpc_id
    vpc_cidr_block                           = data.terraform_remote_state.infrastructure.outputs.vpc_cidr_block
    private_subnet_ids                       = data.terraform_remote_state.infrastructure.outputs.private_subnet_ids
    vpc_endpoints_security_group_id          = data.terraform_remote_state.infrastructure.outputs.vpc_endpoints_security_group_id
    kms_key_arn                              = data.terraform_remote_state.infrastructure.outputs.kms_key_general_arn
    kms_key_id                               = data.terraform_remote_state.infrastructure.outputs.kms_key_general_id
    kms_key_secrets_manager_arn              = data.terraform_remote_state.infrastructure.outputs.kms_key_secrets_manager_arn
    cloudwatch_log_group_infrastructure_name = data.terraform_remote_state.infrastructure.outputs.cloudwatch_log_group_infrastructure_name
    route53_private_zone_id                  = data.terraform_remote_state.infrastructure.outputs.route53_private_zone_id
    route53_private_zone_domain              = data.terraform_remote_state.infrastructure.outputs.route53_private_zone_domain
  }

  # ECR Pull Through Cache upstream URLs (merge default with ACR if configured)
  ecr_pull_through_cache_upstream_urls = merge(
    var.ecr_pull_through_cache_upstream_urls,
    var.acr_registry_url != "" ? {
      (var.acr_registry_url) = var.acr_registry_url
      # Short alias for ACR mirror
      "uniquecr" = var.acr_registry_url
    } : {}
  )
}

