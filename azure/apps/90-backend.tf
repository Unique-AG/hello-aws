terraform {
  backend "azurerm" {
    # Partial config — values come from environments/{env}/backend-config.hcl.
    # State stored in the central INFRA-managed subscription, not the workload sub.
  }
}
