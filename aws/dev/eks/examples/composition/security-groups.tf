module "security_groups" {
  count                 = local.active ? 1 : 0
  source                = "../../modules/aws/security-groups"
  name                  = var.name
  vpc_id                = module.networking[0].vpc_id
  tags                  = var.tags
  rules                 = var.rules
  external_destinations = var.external_destinations
  depends_on            = [terraform_data.approval]
}
