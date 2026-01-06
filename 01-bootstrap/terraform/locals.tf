locals {
  # S3 bucket name using module's s3_bucket_prefix (without account ID)
  # Format: s3-{id_short}-tfstate
  # Example: s3-acme-dogfood-d-euc2-tfstate (dev)
  # Example: s3-acme-dogfood-x-euc2-tfstate (sbx)
  # Note: Environment is already in id_short, account ID not needed if each env has separate account
  s3_bucket_name = "${module.naming.s3_bucket_prefix}-tfstate"

  # KMS key alias with resource moniker, environment, and region
  # Format: alias/kms-{id}-tfstate
  # Example: alias/kms-acme-dogfood-dev-tfstate
  kms_key_alias = "alias/kms-${module.naming.id}-tfstate"

  # Layer name for state file organization
  # This bucket stores state files from all layers, each in its own path
  layer_name = "bootstrap"

  # IAM role name for GitHub Actions using module's iam_role_prefix
  # Format: {iam_role_prefix}-github-actions
  # Example: iam-unique-ai-acme-prod-github-actions
  github_actions_role_name = "${module.naming.iam_role_prefix}-github-actions"


  # Additional tags (merged with naming module tags)
  additional_tags = {
    "client:Name" = var.client_name
  }

  # Combined tags (naming module tags + additional tags)
  tags = merge(module.naming.tags, local.additional_tags)
}
