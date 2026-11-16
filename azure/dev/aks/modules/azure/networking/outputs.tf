output "vnet_id" {
  value = azurerm_virtual_network.this.id
}
output "system_subnet_id" {
  value = one([for name, subnet in local.subnets : azurerm_subnet.this[name].id if subnet.role == "system"])
}
output "user_subnet_id" {
  value = one([for name, subnet in local.subnets : azurerm_subnet.this[name].id if subnet.role == "user"])
}
output "nat_gateway_id" {
  value = azurerm_nat_gateway.this.id
}
output "nat_public_ip" {
  value = azurerm_public_ip.nat.ip_address
}
# The cluster must wait for the NAT associations (outbound type userAssignedNATGateway).
output "egress_ready" {
  value = [for association in azurerm_subnet_nat_gateway_association.this : association.id]
}
