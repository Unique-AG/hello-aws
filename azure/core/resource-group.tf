resource "azurerm_resource_group" "ai" {
  name     = "rg-${local.name_prefix}-ai-${local.name_suffix}"
  location = var.location
  tags     = local.tags
}
