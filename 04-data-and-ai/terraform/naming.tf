module "naming" {
  source = "../../modules/naming"

  org             = var.org
  org_moniker     = var.org_moniker
  product         = var.product
  product_moniker = var.product_moniker
  layer           = "data-and-ai"
  environment     = var.environment

  aws_account_id   = coalesce(var.aws_account_id, data.aws_caller_identity.current.account_id)
  aws_region       = var.aws_region
  semantic_version = var.semantic_version
}
