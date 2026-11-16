output "reader_assignments" {
  description = "Purpose:role keys granted on the cluster (no principal IDs)."
  value       = sort(keys(azurerm_role_assignment.reader))
}
