#######################################
# Naming Module
#######################################
#
# Centralized naming and tagging for all AWS resources.
# Provides consistent naming with AWS service-specific
# length constraints and standard tags.
#######################################

module "naming" {
  source = "../../modules/naming"

  # Required - common across all layers
  org             = var.org
  org_moniker     = var.org_moniker
  product         = var.product
  product_moniker = var.product_moniker
  layer           = "compute"
  environment     = var.environment

  # Deterministic (recommended for CI/CD)
  aws_account_id = coalesce(var.aws_account_id, data.aws_caller_identity.current.account_id)
  aws_region     = var.aws_region

  # Compute tracking
  semantic_version = var.semantic_version
}
