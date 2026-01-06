#######################################
# Naming Module
#######################################
#
# Centralized naming and tagging for all AWS resources.
# Provides consistent naming with AWS service-specific
# length constraints and standard tags.
#
# Uses semantic versioning only (no git references).
#
# TODO: Module source versioning will be refactored to use commit hashes
# instead of tags (e.g., ?ref=abc123def456...) for better reproducibility
# and supply chain security. This is a known improvement item.
#######################################

module "naming" {
  source = "git::https://github.com/gustav-mango-unique-ai/terraform-modules.git//modules/naming?ref=v0.1.2"

  # Required - common across all layers
  org         = var.org
  org_moniker = var.org_moniker
  client      = var.client
  layer       = "compute"
  environment = var.environment

  # Deterministic (recommended for CI/CD)
  aws_account_id = coalesce(var.aws_account_id, data.aws_caller_identity.current.account_id)
  aws_region     = var.aws_region

  # Compute tracking
  semantic_version = var.semantic_version
}
