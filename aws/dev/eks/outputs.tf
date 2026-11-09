output "proposed_names" {
  value = module.naming.names
}
output "resolved_profiles" {
  value = { for role, size in local.requested_profiles : role => local.catalog.nodegroups[role].sizes[size] }
}
output "design_status" {
  value = {
    status                = local.execution ? "EXECUTION_MODE" : "DRAFT_BLOCKED"
    mode                  = var.proposal_mode
    infrastructure_status = "NOT_EXECUTED"
    deployment_authorized = false
    application_code      = var.application_code
  }
}
output "proposed_subnet_names" {
  description = "Subnet names for review; empty until Networking supplies CIDRs."
  value       = module.naming.subnet_names
}
output "networking_status" {
  value = {
    networking   = local.networking_ready ? "READY" : "PENDING"
    connectivity = local.connectivity_ready ? "READY" : "PENDING"
    cluster      = local.cluster_ready ? "READY" : "PENDING"
  }
}
output "network" {
  description = "Network IDs once created; null in design mode."
  value = local.networking_ready ? {
    vpc_id             = module.networking[0].vpc_id
    public_subnet_ids  = module.networking[0].public_subnet_ids
    cluster_subnet_ids = module.networking[0].cluster_subnet_ids
    node_subnet_ids    = module.networking[0].node_subnet_ids
    nat_gateway_ids    = module.networking[0].nat_gateway_ids
    nat_public_ips     = module.networking[0].nat_public_ips
  } : null
}
