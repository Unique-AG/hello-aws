locals {
  # Layer name for state file organization
  layer_name = "governance"

  # Additional tags (merged with naming module tags)
  additional_tags = {
    "client:Name" = var.client_name
  }

  # Combined tags (naming module tags + additional tags)
  tags = merge(module.naming.tags, local.additional_tags)
}

