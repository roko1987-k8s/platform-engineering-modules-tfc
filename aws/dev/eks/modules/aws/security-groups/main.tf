resource "aws_security_group" "role" {
  for_each    = toset(["control_plane", "system", "user"])
  name_prefix = "${var.name}-${replace(each.key, "_", "-")}-"
  description = "Explicit approved ${each.key} flows only; no default egress"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-${each.key}" })
  lifecycle { create_before_destroy = true }
}
# aws_security_group removes AWS's automatically added allow-all egress on creation.
# No inline rules are mixed with the standalone ownership below.
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
  groups           = merge({ for k, sg in aws_security_group.role : k => sg.id }, { for k, sg in data.aws_security_group.external : k => sg.id })
  internal_ingress = { for id, r in var.rules : id => r if contains(["system", "user", "control_plane"], r.destination) }
}
resource "aws_vpc_security_group_egress_rule" "approved" {
  for_each                     = var.rules
  security_group_id            = local.groups[each.value.source]
  referenced_security_group_id = local.groups[each.value.destination]
  ip_protocol                  = each.value.protocol
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  description                  = "${each.value.relation}: ${each.value.approval_reference}"
  tags                         = merge(var.tags, { RuleId = each.key, Relation = each.value.relation })
}
resource "aws_vpc_security_group_ingress_rule" "approved" {
  for_each                     = local.internal_ingress
  security_group_id            = local.groups[each.value.destination]
  referenced_security_group_id = local.groups[each.value.source]
  ip_protocol                  = each.value.protocol
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  description                  = "${each.value.relation}: ${each.value.approval_reference}"
  tags                         = merge(var.tags, { RuleId = each.key, Relation = each.value.relation })
}
