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
output "security_groups" {
  description = "Own security groups and RuleIds; null in design mode."
  value = length(module.security_groups) == 0 ? null : {
    ids              = module.security_groups[0].security_group_ids
    cluster          = module.security_groups[0].cluster_security_group_id
    rules            = module.security_groups[0].rules
    implicit_denials = module.security_groups[0].implicit_denials
  }
}
output "load_balancer_controller" {
  description = "Values the tools need to install the AWS Load Balancer Controller; null in design mode."
  value = length(module.load_balancer_controller) == 0 ? null : {
    cluster_name              = module.eks[0].name
    vpc_id                    = module.networking[0].vpc_id
    service_account           = module.load_balancer_controller[0].service_account
    role_arn                  = module.iam[0].lb_controller_role_arn
    ingress_security_group_id = module.security_groups[0].ingress_security_group_id
  }
}
output "access" {
  description = "Cluster access (TD-049); null when no access was injected."
  value = length(module.access) == 0 ? null : {
    jump_instance_id         = module.access[0].jump_instance_id
    bot_role_arn             = module.access[0].bot_role_arn
    tools_role_arn           = module.access[0].tools_role_arn
    platform_admin_role_arns = module.access[0].platform_admin_role_arns
  }
}
