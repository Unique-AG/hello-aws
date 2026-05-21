output "foundry_endpoint" {
  description = "Azure AI Foundry endpoint URL"
  value       = azurerm_cognitive_account.foundry.endpoint
}

output "foundry_account_name" {
  description = "Azure AI Foundry account name"
  value       = azurerm_cognitive_account.foundry.name
}

output "foundry_primary_key" {
  description = "Azure AI Foundry primary access key"
  value       = azurerm_cognitive_account.foundry.primary_access_key
  sensitive   = true
}

output "gpt4o_deployment_name" {
  description = "GPT-4o deployment name"
  value       = azurerm_cognitive_deployment.gpt4o.name
}
