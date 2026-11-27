output "resource_group" {
  description = "Workspace resource group (name and ID); the AKS workspace reads it by name."
  value = {
    name = azurerm_resource_group.workspace.name
    id   = azurerm_resource_group.workspace.id
  }
}

output "storage_account_id" {
  description = "State Storage Account ID for reviewed consumer role assignments."
  value       = azurerm_storage_account.state.id
}

output "backend" {
  description = "Values of the consumers' backend \"azurerm\" configuration (the key and the subscription are set per workspace)."
  value = {
    resource_group_name  = azurerm_resource_group.workspace.name
    storage_account_name = azurerm_storage_account.state.name
    container_name       = azurerm_storage_container.state.name
    use_azuread_auth     = true
  }
}
