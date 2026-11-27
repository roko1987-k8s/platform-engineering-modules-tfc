output "reader_assignments" {
  description = "Purpose:role keys granted on the cluster (no principal IDs)."
  value       = sort(keys(azurerm_role_assignment.reader))
}
output "agent_access" {
  description = "Agent purposes and invoker kinds granted on the cluster (no principal IDs)."
  value = {
    agents         = sort(keys(local.agents))
    command_invoke = sort([for key in keys(local.invokers) : split(":", key)[0]])
  }
}
