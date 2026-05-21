terraform {
  # < 1.14 required: azurerm provider OIDC backend access regresses on 1.14+.
  required_version = ">= 1.10.0, < 1.14.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
