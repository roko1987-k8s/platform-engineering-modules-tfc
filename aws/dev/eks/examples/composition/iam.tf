module "iam" {
  count              = local.active ? 1 : 0
  source             = "../../modules/aws/iam"
  name               = var.name
  tags               = var.tags
  pod_identity_roles = var.pod_identity_roles
  depends_on         = [terraform_data.approval, module.networking]
}
