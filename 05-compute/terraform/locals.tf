locals {
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
    public_subnet_ids                        = data.terraform_remote_state.infrastructure.outputs.public_subnet_ids
    vpc_endpoints_security_group_id          = data.terraform_remote_state.infrastructure.outputs.vpc_endpoints_security_group_id
    kms_key_arn                              = data.terraform_remote_state.infrastructure.outputs.kms_key_general_arn
    kms_key_id                               = data.terraform_remote_state.infrastructure.outputs.kms_key_general_id
    kms_key_secrets_manager_arn              = data.terraform_remote_state.infrastructure.outputs.kms_key_secrets_manager_arn
    cloudwatch_log_group_infrastructure_name = data.terraform_remote_state.infrastructure.outputs.cloudwatch_log_group_infrastructure_name
    route53_private_zone_id                  = data.terraform_remote_state.infrastructure.outputs.route53_private_zone_id
    route53_private_zone_domain              = data.terraform_remote_state.infrastructure.outputs.route53_private_zone_domain
    ingress_nlb_security_group_id            = try(data.terraform_remote_state.infrastructure.outputs.ingress_nlb_security_group_id, null)
  }

  # ACR alias extracted from registry URL (e.g., "uniqueapp" from "uniqueapp.azurecr.io")
  acr_alias = var.acr_registry_url != "" ? split(".azurecr.io", var.acr_registry_url)[0] : ""

  # ECR Pull Through Cache upstream URLs (merge default with ACR if configured)
  # When ACR is configured, register both the full URL and the short alias as cache prefixes
  acr_upstream_urls = var.acr_registry_url != "" ? merge(
    { (var.acr_registry_url) = var.acr_registry_url },
    local.acr_alias != var.acr_registry_url ? { (local.acr_alias) = var.acr_registry_url } : {}
  ) : {}
  ecr_pull_through_cache_upstream_urls = merge(
    var.ecr_pull_through_cache_upstream_urls,
    local.acr_upstream_urls
  )
}

