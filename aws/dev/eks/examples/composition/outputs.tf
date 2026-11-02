output "cluster" {
  value = local.active ? { name = module.eks[0].name, arn = module.eks[0].arn, endpoint = module.eks[0].endpoint, certificate_authority_data = module.eks[0].certificate_authority_data } : null
}
output "nodegroups" {
  value = local.active ? module.nodegroups[0].groups : null
}
output "catalogue" {
  value = { commit = var.catalog_commit_sha, digest = filesha256(var.catalog_path), networking = local.catalog.networking.conformity }
}
