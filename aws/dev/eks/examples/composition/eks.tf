module "eks" {
  count                           = local.active ? 1 : 0
  source                          = "../../modules/aws/eks"
  name                            = var.name
  catalog                         = local.catalog
  kubernetes_version              = var.kubernetes_version
  region                          = var.region
  role_arn                        = module.iam[0].cluster_role_arn
  subnet_ids                      = module.networking[0].cluster_subnet_ids
  control_plane_security_group_id = module.security_groups[0].security_group_ids.control_plane
  kms_key_arn                     = var.kms_key_arn
  log_retention_days              = var.log_retention_days
  tags                            = var.tags
  depends_on                      = [terraform_data.approval]
}
