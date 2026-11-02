module "foundation_addons" {
  count        = local.active ? 1 : 0
  source       = "../../modules/aws/addons"
  cluster_name = module.eks[0].name
  addons       = { for name, a in var.addons : name => a if name != "coredns" }
  tags         = var.tags
  depends_on   = [module.iam]
}
module "dns_addon" {
  count        = local.active ? 1 : 0
  source       = "../../modules/aws/addons"
  cluster_name = module.eks[0].name
  addons       = { for name, a in var.addons : name => a if name == "coredns" }
  tags         = var.tags
  depends_on   = [module.nodegroups]
}
