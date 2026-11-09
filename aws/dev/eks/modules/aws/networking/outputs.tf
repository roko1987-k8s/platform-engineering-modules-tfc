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
