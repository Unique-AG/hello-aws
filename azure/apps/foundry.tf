# Azure AI Foundry account + GPT-4o deployment.
# Public network access enabled; private endpoints are a planned follow-up.

# 4-char random suffix on the subdomain only — the subdomain is a global Azure
# DNS label and `apply` fails if the name is taken. The account `name` stays
# deterministic so terraform state is stable; the lifecycle ignore_changes on
# random_string keeps the suffix fixed across re-applies.
resource "random_string" "foundry_subdomain_suffix" {
  length  = 4
  special = false
  upper   = false

  lifecycle {
    ignore_changes = [length, special, upper, numeric, lower]
  }
}

resource "azurerm_cognitive_account" "foundry" {
  name                          = "ai-${local.name_prefix}-${local.name_suffix}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  kind                          = "AIServices"
  sku_name                      = var.foundry_sku
  custom_subdomain_name         = "ai-${local.name_prefix}-${local.name_suffix}-${random_string.foundry_subdomain_suffix.result}"
  public_network_access_enabled = true
  local_auth_enabled            = true

  tags = local.tags
}

resource "azurerm_cognitive_deployment" "gpt4o" {
  name                 = "gpt-4o"
  cognitive_account_id = azurerm_cognitive_account.foundry.id

  model {
    format  = "OpenAI"
    name    = "gpt-4o"
    version = var.gpt4o_model_version
  }

  sku {
    name     = "Standard"
    capacity = var.gpt4o_capacity
  }
}
