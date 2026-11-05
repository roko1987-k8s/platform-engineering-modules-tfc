output "proposed_names" {
  value = module.naming.names
}
output "resolved_profiles" {
  value = { for role, size in local.requested_profiles : role => local.catalog.nodegroups[role].sizes[size] }
}
output "design_status" {
  value = { status = "DRAFT_BLOCKED", infrastructure_status = "NOT_EXECUTED", deployment_authorized = false, application_code = var.application_code }
}
