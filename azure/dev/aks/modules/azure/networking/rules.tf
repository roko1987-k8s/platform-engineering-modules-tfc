# Azure translation of network/rules.yaml (the rules of every cluster, defined once for all
# clouds), as inbound rules on the NSG of each node subnet. Endpoints:
#   system, user   node subnet prefixes (pods share them with classic Azure CNI)
#   lb             as destination: the internal load balancer subnet prefix. Azure keeps the
#                  frontend IP as the packet destination (floating IP), so the rule lives on
#                  the User NSG, where the Istio gateway pods run.
#                  as source: the AzureLoadBalancer tag (health probes). Probes reach the node
#                  ports AKS assigns to the Service, so 30000-32767 joins the rule's ports.
#   any            "*"
#   control_plane  no Azure object (the managed control plane reaches the nodes through its
#                  own tunnel); rules marked "not applicable" for azure are skipped.
#   jump           no Azure object: there is no jump host, the private API is reached with
#                  az aks command invoke through the Azure API (modules/azure/access).
# Priority = catalog rule id: the custom range (150-199) stays free and the denials (210,
# 212) are explicit DenyAll rules, so Azure's default inbound rules (65000+) are never
# reached. Egress keeps Azure's defaults (open until rule 502).
locals {
  node_roles = ["system", "user"]
  role_cidr  = { for subnet in values(local.subnets) : subnet.role => subnet.cidr }
  nsg_name   = { for name, subnet in local.subnets : subnet.role => azurerm_network_security_group.this[name].name }
  source_prefix = merge(
    { any = "*", lb = "AzureLoadBalancer" },
    { for role in local.node_roles : role => local.role_cidr[role] },
  )
  node_ports = "30000-32767"

  catalogue = {
    for id, rule in var.rules_catalog.rules : id => rule
    if try(rule.status, "active") == "active" && !startswith(try(rule.clouds.azure, ""), "not applicable")
  }
  # One NSG rule per catalog rule and destination NSG; a duplicate key (two destinations
  # landing on the same NSG with the same priority) fails the plan instead of overwriting.
  candidates = merge([
    for id, rule in local.catalogue : {
      for destination in rule.destinations : "${id}-${destination == "lb" ? "user" : destination}" => {
        rule               = id
        destination        = destination
        nsg_role           = destination == "lb" ? "user" : destination
        destination_prefix = local.role_cidr[destination]
        sources            = contains(rule.sources, "any") ? ["*"] : distinct([for source in rule.sources : local.source_prefix[source] if contains(keys(local.source_prefix), source)])
        protocol           = rule.protocol == "all" ? "*" : title(rule.protocol)
        ports              = rule.protocol == "all" ? ["*"] : concat(rule.ports, contains(rule.sources, "lb") ? [local.node_ports] : [])
        description        = "${id} ${rule.description}"
      } if contains(keys(local.role_cidr), destination)
    }
  ]...)
  allow_rules = { for key, rule in local.candidates : key => rule if length(rule.sources) > 0 && length(rule.ports) > 0 }

  deny_rules = {
    for id, denial in try(var.rules_catalog.denials, {}) : "${id}-${denial.destination}" => {
      rule        = id
      nsg_role    = denial.destination
      description = "${id} ${denial.description}"
    } if contains(local.node_roles, denial.destination)
  }
}

resource "azurerm_network_security_rule" "allow" {
  for_each                    = local.allow_rules
  name                        = "adp-${each.value.rule}-${each.value.destination}"
  resource_group_name         = var.resource_group_name
  network_security_group_name = local.nsg_name[each.value.nsg_role]
  priority                    = tonumber(each.value.rule)
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = each.value.protocol
  source_port_range           = "*"
  source_address_prefix       = length(each.value.sources) == 1 ? each.value.sources[0] : null
  source_address_prefixes     = length(each.value.sources) == 1 ? null : each.value.sources
  destination_address_prefix  = each.value.destination_prefix
  destination_port_range      = length(each.value.ports) == 1 ? each.value.ports[0] : null
  destination_port_ranges     = length(each.value.ports) == 1 ? null : each.value.ports
  description                 = substr(each.value.description, 0, 140)
}

resource "azurerm_network_security_rule" "deny" {
  for_each                    = local.deny_rules
  name                        = "adp-${each.value.rule}-deny-${each.value.nsg_role}"
  resource_group_name         = var.resource_group_name
  network_security_group_name = local.nsg_name[each.value.nsg_role]
  priority                    = tonumber(each.value.rule)
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  destination_port_range      = "*"
  description                 = substr(each.value.description, 0, 140)
}
