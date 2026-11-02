module "nodegroups" {
  count              = local.active ? 1 : 0
  source             = "../../modules/aws/nodegroups"
  cluster_name       = module.eks[0].name
  kubernetes_version = var.kubernetes_version
  catalog            = local.catalog
  subnet_ids         = module.networking[0].node_subnet_ids
  node_role_arns     = module.iam[0].node_role_arns
  security_group_ids = module.security_groups[0].security_group_ids
  selections         = var.selections
  root_volumes       = var.root_volumes
  tags               = var.tags
  depends_on         = [module.foundation_addons]
}
