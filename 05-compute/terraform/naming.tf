#######################################
# Naming Module
#######################################
#
# Centralized naming and tagging for all AWS resources.
# Ensures consistent naming conventions across all layers.
#
# TODO: Module source versioning will be refactored to use commit hashes
# instead of tags (e.g., ?ref=abc123def456...) for better reproducibility
# and supply chain security. This is a known improvement item.
#######################################

module "naming" {
  source = "git::https://github.com/gustav-mango-unique-ai/terraform-modules.git//modules/naming?ref=v0.1.2"

  org         = var.org
  org_moniker = var.org_moniker
  client      = var.client
  layer       = "compute"
  environment = var.environment

  aws_account_id = coalesce(var.aws_account_id, data.aws_caller_identity.current.account_id)
  aws_region     = var.aws_region

  semantic_version = var.semantic_version
}

