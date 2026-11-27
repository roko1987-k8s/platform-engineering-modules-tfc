output "resource_group" {
  description = "Workspace resource group (name and ID)."
  value       = module.state.resource_group
}

output "backend" {
  description = "Values of the consumers' backend \"azurerm\" configuration."
  value       = module.state.backend
}
