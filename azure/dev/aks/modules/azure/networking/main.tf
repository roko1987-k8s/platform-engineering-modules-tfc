locals {
  subnets = merge(
    { for i, cidr in var.networking.system_subnet_cidrs : var.subnet_names.system[i] => { role = "system", cidr = cidr } },
    { for i, cidr in var.networking.user_subnet_cidrs : var.subnet_names.user[i] => { role = "user", cidr = cidr } },
    { for i, cidr in var.networking.lb_subnet_cidrs : var.subnet_names.lb[i] => { role = "lb", cidr = cidr } },
  )
  # Only node subnets need egress; the internal load balancer subnet holds frontend IPs only.
  node_subnets = { for name, subnet in local.subnets : name => subnet if subnet.role != "lb" }
}

resource "azurerm_virtual_network" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.networking.vnet_cidr]
  tags                = merge(var.tags, { ApprovalReference = var.networking.approval_reference })
}

resource "azurerm_subnet" "this" {
  for_each             = local.subnets
  name                 = each.key
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value.cidr]
}

# One NSG per subnet. Node subnets carry the Azure translation of network/rules.yaml
# (rules.tf); AKS also manages its own rules on the node NSG of its resource group.
resource "azurerm_network_security_group" "this" {
  for_each            = local.subnets
  name                = "${each.key}-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each                  = local.subnets
  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = azurerm_network_security_group.this[each.key].id
}

# Explicit egress (outbound_type userAssignedNATGateway), as the NAT gateway in AWS.
resource "azurerm_public_ip" "nat" {
  name                = "${var.name}-nat-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway" "this" {
  name                    = "${var.name}-nat"
  location                = var.location
  resource_group_name     = var.resource_group_name
  sku_name                = "Standard"
  idle_timeout_in_minutes = 10
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  nat_gateway_id       = azurerm_nat_gateway.this.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "this" {
  for_each       = local.node_subnets
  subnet_id      = azurerm_subnet.this[each.key].id
  nat_gateway_id = azurerm_nat_gateway.this.id
}
