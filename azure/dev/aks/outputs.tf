output "proposed_names" {
  value = module.naming.names
}
output "resolved_profiles" {
  value = { for role, size in local.requested_profiles : role => local.catalog.nodepools[role].sizes[size] }
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
  description = "Subnet names for review; empty until the network catalog supplies CIDRs."
  value       = module.naming.subnet_names
}
output "networking_status" {
  value = {
    networking = local.networking_ready ? "READY" : "PENDING"
    access     = local.access_ready ? "READY" : "PENDING"
    cluster    = local.cluster_ready ? "READY" : "PENDING"
  }
}
output "network" {
  description = "Network IDs once created; null in design mode."
  value = local.networking_ready ? {
    vnet_id          = module.networking[0].vnet_id
    system_subnet_id = module.networking[0].system_subnet_id
    user_subnet_id   = module.networking[0].user_subnet_id
    nat_gateway_id   = module.networking[0].nat_gateway_id
    nat_public_ip    = module.networking[0].nat_public_ip
  } : null
}
output "cluster" {
  description = "Private cluster facts once created; null otherwise."
  value = local.cluster_ready ? {
    name            = module.aks[0].name
    private_fqdn    = module.aks[0].private_fqdn
    oidc_issuer_url = module.aks[0].oidc_issuer_url
  } : null
}
