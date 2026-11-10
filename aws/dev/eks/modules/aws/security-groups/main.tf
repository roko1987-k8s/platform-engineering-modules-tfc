# No security group is created here. EKS creates and owns the cluster security
# group (control-plane ENIs and managed nodes share it); this module only adds
# approved rules on it. EKS-managed rules on that SG (not owned here):
#   - ingress: all traffic from the cluster SG itself (control plane <-> nodes,
#     node <-> node: API 443, kubelet 10250, DNS 53, pod traffic);
#   - egress: all traffic to 0.0.0.0/0 (NAT Gateway; ECR, S3, STS, EKS).
# Approved flows between system, user and control_plane are therefore already
# covered and create no resource (output covered_by_eks).
data "aws_security_group" "external" {
  for_each = var.external_destinations
  id       = each.value
  lifecycle {
    postcondition {
      condition     = self.vpc_id == var.vpc_id
      error_message = "Reviewed endpoint SGs must belong to the approved VPC."
    }
  }
}
locals {
  internal       = ["system", "user", "control_plane"]
  covered_by_eks = { for id, r in var.rules : id => r if contains(local.internal, r.destination) }
  # Flows to reviewed endpoint SGs: explicit egress from the cluster SG, kept in
  # Terraform so they survive a later, separately approved egress restriction.
  # Inbound on the endpoint SG remains the endpoint owner's responsibility.
  external_egress = { for id, r in var.rules : id => r if !contains(local.internal, r.destination) }
}
resource "aws_vpc_security_group_egress_rule" "approved" {
  for_each                     = local.external_egress
  security_group_id            = var.cluster_security_group_id
  referenced_security_group_id = data.aws_security_group.external[each.value.destination].id
  ip_protocol                  = each.value.protocol
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  description                  = "${each.value.relation}: ${each.value.approval_reference}"
  tags                         = merge(var.tags, { RuleId = each.key, Relation = each.value.relation })
}
