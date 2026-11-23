output "security_group_ids" {
  description = "Own security groups of the instance; ingress goes to the Istio gateway annotation."
  value       = { for role, sg in aws_security_group.role : role => sg.id }
}
output "node_security_group_ids" {
  value = { system = aws_security_group.role["system"].id, user = aws_security_group.role["user"].id }
}
output "ingress_security_group_id" {
  value = aws_security_group.role["ingress"].id
}
output "cluster_security_group_id" {
  description = "EKS-created group, control plane only."
  value       = var.cluster_security_group_id
}
output "rules" {
  description = "Active logical rules (network/rules.yaml plus custom) by RuleId, with all their ports."
  value = merge(
    { for id, r in local.catalogue : id => { sources = r.sources, destinations = r.destinations, protocol = r.protocol, ports = r.ports } },
    { for id, r in local.custom : r.rule => { sources = r.sources, destinations = r.destinations, protocol = r.protocol, ports = r.ports } },
  )
}
output "implicit_denials" {
  value = merge(
    { for id, d in var.rules_catalog.denials : id => d.description },
    { "502" = "not applied: node egress open until application delivery" },
  )
}
