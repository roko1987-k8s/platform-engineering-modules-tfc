output "vpc_id" {
  value      = data.aws_vpc.approved.id
  depends_on = [terraform_data.validation]
}
output "cluster_subnet_ids" {
  value      = var.cluster_subnet_ids
  depends_on = [terraform_data.validation]
}
output "node_subnet_ids" {
  value      = var.node_subnet_ids
  depends_on = [terraform_data.validation]
}
output "connectivity" {
  value = var.connectivity
}
