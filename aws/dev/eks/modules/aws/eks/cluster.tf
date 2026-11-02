data "aws_region" "current" {}
resource "aws_eks_cluster" "this" {
  name                          = var.name
  version                       = var.kubernetes_version
  role_arn                      = var.role_arn
  enabled_cluster_log_types     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  bootstrap_self_managed_addons = false
  deletion_protection           = true
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }
  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = [var.control_plane_security_group_id]
    endpoint_private_access = true
    endpoint_public_access  = false
  }
  encryption_config {
    provider { key_arn = var.kms_key_arn }
    resources = ["secrets"]
  }
  tags       = var.tags
  depends_on = [aws_cloudwatch_log_group.control_plane]
  lifecycle {
    precondition {
      condition     = data.aws_region.current.region == var.region
      error_message = "Provider region must match the approved selection."
    }
  }
}
