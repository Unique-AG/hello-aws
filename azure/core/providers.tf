provider "azurerm" {
  subscription_id = var.subscription_id
  use_oidc        = true

  features {}
}
