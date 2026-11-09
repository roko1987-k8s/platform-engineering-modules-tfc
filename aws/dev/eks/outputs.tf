output "proposed_names" {
  value = module.naming.names
}
output "resolved_profiles" {
  value = { for role, size in local.requested_profiles : role => local.catalog.nodegroups[role].sizes[size] }
}
output "design_status" {
  value = { status = "DRAFT_BLOCKED", infrastructure_status = "NOT_EXECUTED", deployment_authorized = false, application_code = var.application_code }
}
output "proposed_subnet_names" {
  description = "Subnet names for review; empty until Networking supplies CIDRs."
  value       = module.naming.subnet_names
}
output "networking_status" {
  value = {
    networking   = local.networking_ready ? "READY" : "PENDING"
    connectivity = local.connectivity_ready ? "READY" : "PENDING"
  }
}
