output "cluster_security_group_id" {
  value = var.cluster_security_group_id
}
output "approved_rules" {
  value = var.rules
}
output "covered_by_eks" {
  description = "Approved flows already allowed by the EKS-managed self-referencing rule; no resource is created."
  value       = { for id, r in local.covered_by_eks : id => r.relation }
}
output "terraform_managed_rules" {
  value = { for id, r in aws_vpc_security_group_egress_rule.approved : id => r.id }
}
output "eks_managed_rules" {
  value = { ingress = "all traffic from the cluster security group itself", egress = "all traffic to 0.0.0.0/0" }
}
output "implicit_denials" {
  value = { "500" = "unmatched ingress to System (outside the cluster SG)", "501" = "unmatched ingress to User (outside the cluster SG)", "502" = "not applied: EKS-managed egress allows all; restricting it needs a separate approval" }
}
