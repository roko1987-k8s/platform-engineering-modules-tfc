# New installation only. Confirm no previous infrastructure/state before deployment.
provider "azurerm" {
  subscription_id     = var.subscription_id
  storage_use_azuread = true
  # Resource providers are registered once per subscription by the owner: the execution
  # identity has no subscription-wide register permission (E3).
  resource_provider_registrations = "none"
  features {
    storage {
      # Manage everything through Azure Resource Manager (no data plane calls,
      # whatever the network access model).
      data_plane_available = false
    }
  }
}

module "state" {
  source = "../modules/state"

  resource_group_name  = "rgeusd900dev01"
  storage_account_name = "steusd900dev01"
  location             = "eastus"
  network_access       = var.network_access
  allowed_ip_ranges    = var.allowed_ip_ranges
  tags = {
    teamId      = "D900"
    environment = "dev"
  }
}
