locals {
  # Layer name for state file organization
  layer_name = "data-and-ai"

  # Terraform state bucket name (computed from naming module, same as bootstrap layer)
  # Format: s3-{id_short}-tfstate
  terraform_state_bucket = "${module.naming.s3_bucket_prefix}-tfstate"

  # KMS key alias for Terraform state encryption (computed from naming module, same as bootstrap layer)
  # Format: alias/kms-{id}-tfstate
  terraform_state_kms_key_id = "alias/kms-${module.naming.id}-tfstate"

  tags = module.naming.tags

  # Infrastructure layer outputs (from remote state)
  infrastructure = {
    vpc_id                      = data.terraform_remote_state.infrastructure.outputs.vpc_id
    isolated_subnet_ids         = data.terraform_remote_state.infrastructure.outputs.isolated_subnet_ids
    private_subnet_ids          = data.terraform_remote_state.infrastructure.outputs.private_subnet_ids
    kms_key_general_arn         = data.terraform_remote_state.infrastructure.outputs.kms_key_general_arn
    kms_key_secrets_manager_arn = data.terraform_remote_state.infrastructure.outputs.kms_key_secrets_manager_arn
    kms_key_cloudwatch_logs_arn = data.terraform_remote_state.infrastructure.outputs.kms_key_cloudwatch_logs_arn
    s3_gateway_endpoint_id      = try(data.terraform_remote_state.infrastructure.outputs.s3_gateway_endpoint_id, null)
    kms_key_prometheus_arn      = try(data.terraform_remote_state.infrastructure.outputs.kms_key_prometheus_arn, null)
    kms_key_grafana_arn         = try(data.terraform_remote_state.infrastructure.outputs.kms_key_grafana_arn, null)
  }
}
