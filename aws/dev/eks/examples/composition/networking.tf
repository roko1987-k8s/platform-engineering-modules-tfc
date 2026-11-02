module "networking" {
  count              = local.active ? 1 : 0
  source             = "../../modules/aws/networking"
  vpc_id             = var.vpc_id
  cluster_subnet_ids = var.cluster_subnet_ids
  node_subnet_ids    = var.node_subnet_ids
  conformity         = local.catalog.networking.conformity
  connectivity       = var.connectivity
  depends_on         = [terraform_data.approval]
}
