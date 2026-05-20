output "resource_group_name" {
  description = "Name of the AI resource group"
  value       = azurerm_resource_group.ai.name
}

output "resource_group_id" {
  description = "ID of the AI resource group"
  value       = azurerm_resource_group.ai.id
}

output "location" {
  description = "Azure region"
  value       = azurerm_resource_group.ai.location
}
