# Same output names as before, so EKS, Nodegroups and Security Groups are unchanged.
output "vpc_id" {
  value = aws_vpc.this.id
}
output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}
output "cluster_subnet_ids" {
  description = "In the order of networking.cluster_subnet_cidrs."
  value       = [for name in var.subnet_names.cluster : aws_subnet.this[name].id]
}
output "node_subnet_ids" {
  description = "In the order of networking.node_subnet_cidrs."
  value       = [for name in var.subnet_names.node : aws_subnet.this[name].id]
}
output "public_subnet_ids" {
  description = "NAT subnets, in the order of networking.public_subnet_cidrs."
  value       = [for name in var.subnet_names.public : aws_subnet.this[name].id]
}
output "internet_gateway_id" {
  value = aws_internet_gateway.this.id
}
output "nat_gateway_ids" {
  description = "Per public subnet name."
  value       = { for name, nat in aws_nat_gateway.this : name => nat.id }
}
output "nat_public_ips" {
  description = "Egress addresses to register with external allowlists."
  value       = { for name, eip in aws_eip.nat : name => eip.public_ip }
}
output "private_route_table_ids" {
  description = "Per availability zone; default route through its NAT Gateway."
  value       = { for zone, rt in aws_route_table.private : zone => rt.id }
}
output "availability_zones" {
  description = "Zones used, sorted; at least two."
  value       = local.zones
}
output "subnets" {
  description = "Per subnet name: role, CIDR, availability zone and ID."
  value       = { for name, subnet in local.subnets : name => merge(subnet, { id = aws_subnet.this[name].id }) }
}
output "connectivity" {
  value = var.networking.connectivity
}
output "connectivity_ready" {
  description = "True only when Networking attested routing, private API, DNS and ECR/S3/STS/EKS reachability."
  value       = local.connectivity_ready
}
