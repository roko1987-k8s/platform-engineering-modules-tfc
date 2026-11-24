# AWS translation of network/rules.yaml (the rules of every cluster, defined once for all
# clouds). Own security groups of the instance (names from module.naming, prefix "sg"):
#   <sg>-system   managed nodes of the System group          (endpoint system)
#   <sg>-user     managed nodes of the User group            (endpoint user)
#   <sg>-ingress  internal NLB of the Istio gateway          (endpoint lb; passed to the AWS
#                 Load Balancer Controller by annotation, so it creates no k8s-* group)
#   EKS cluster security group, control plane only           (endpoint control_plane)
#   SSM jump host group from modules/aws/access              (endpoint jump)
#   0.0.0.0/0                                                 (endpoint any)
#
# Every catalogue rule expands into one AWS rule per source x destination x port range
# (AWS takes one contiguous range per rule), all tagged with the same RuleId:
#   - ingress half on the destination group, always (source "any" = 0.0.0.0/0; a source
#     already covered by "any" in the same rule only gets its egress half);
#   - egress half on the source group when its egress is not open (lb, jump).
# Security groups have no order and no deny: anything not allowed is denied (210/212).

locals {
  roles = toset(["system", "user", "ingress"])
  sg_id = {
    system        = aws_security_group.role["system"].id
    user          = aws_security_group.role["user"].id
    lb            = aws_security_group.role["ingress"].id
    control_plane = var.cluster_security_group_id
    jump          = var.jump_security_group_id
  }
  # Sources whose egress is already open: no egress half needed.
  open_egress = ["system", "user", "control_plane"]
  # Endpoints that exist in this instance (the jump host only with access).
  present = concat(["any", "lb", "system", "user", "control_plane"], var.jump_enabled ? ["jump"] : [])

  catalogue = {
    for id, r in var.rules_catalog.rules : id => {
      rule         = id
      sources      = r.sources
      destinations = r.destinations
      protocol     = r.protocol
      ports        = try(r.ports, [])
      description  = r.description
    } if try(r.status, "active") == "active"
  }
  custom = {
    for id, r in var.custom_rules : "custom-${id}" => {
      rule         = r.rule
      sources      = [r.source]
      destinations = [r.destination]
      protocol     = r.protocol
      ports        = r.ports
      description  = "${r.source} to ${r.destination}: ${r.approval_reference}"
    }
  }

  pieces = merge([
    for key, r in merge(local.catalogue, local.custom) : {
      for item in setproduct(r.sources, r.destinations, r.protocol == "all" ? ["all"] : r.ports) :
      "${r.rule}-${item[0]}-${item[1]}-${item[2]}" => {
        rule        = r.rule
        source      = item[0]
        destination = item[1]
        protocol    = r.protocol == "all" ? "-1" : r.protocol
        from_port   = item[2] == "all" ? null : tonumber(split("-", item[2])[0])
        to_port     = item[2] == "all" ? null : tonumber(element(split("-", item[2]), length(split("-", item[2])) - 1))
        ingress     = item[0] == "any" || !contains(r.sources, "any")
        egress      = item[0] != "any" && !contains(local.open_egress, item[0])
        description = "${r.rule} ${r.description}"
      } if contains(local.present, item[0]) && contains(local.present, item[1])
    }
  ]...)
}

resource "aws_security_group" "role" {
  for_each    = local.roles
  name        = "${var.name}-${each.key}"
  description = "ADP ${each.key} security group of ${var.cluster_name} (explicit rules only)"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-${each.key}", SecurityGroupRole = each.key })
  # Terraform removes the default allow-all egress; egress is explicit below.
  # Interfaces created outside Terraform (load balancers, CloudShell) release the group
  # some minutes after their owner deletes them: wait in the same Destroy run.
  timeouts {
    delete = "30m"
  }
}

# Ingress half, on the destination group.
resource "aws_vpc_security_group_ingress_rule" "rule" {
  for_each                     = { for id, p in local.pieces : id => p if p.ingress }
  security_group_id            = local.sg_id[each.value.destination]
  cidr_ipv4                    = each.value.source == "any" ? "0.0.0.0/0" : null
  referenced_security_group_id = each.value.source == "any" ? null : lookup(local.sg_id, each.value.source, lookup(var.external_sources, each.value.source, null))
  ip_protocol                  = each.value.protocol
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  description                  = each.value.description
  tags                         = merge(var.tags, { RuleId = each.value.rule, Name = each.key })
}

# Egress half, on a source group whose egress is closed (the NLB group, the jump host).
resource "aws_vpc_security_group_egress_rule" "rule" {
  for_each                     = { for id, p in local.pieces : id => p if p.egress }
  security_group_id            = local.sg_id[each.value.source]
  referenced_security_group_id = local.sg_id[each.value.destination]
  ip_protocol                  = each.value.protocol
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  description                  = each.value.description
  tags                         = merge(var.tags, { RuleId = each.value.rule, Name = "${each.key}-egress" })
}

# Nodes keep unrestricted egress (NAT: ECR, S3, STS, EKS) until application delivery;
# then rule 502: TCP 443 plus the egress half of every rule (catalogue: egress.nodes).
resource "aws_vpc_security_group_egress_rule" "nodes_out" {
  for_each          = toset(["system", "user"])
  security_group_id = local.sg_id[each.key]
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Egress of ${each.key} nodes (502 restriction not applied)"
  tags              = merge(var.tags, { RuleId = "egress", Name = "egress-${each.key}" })
}
