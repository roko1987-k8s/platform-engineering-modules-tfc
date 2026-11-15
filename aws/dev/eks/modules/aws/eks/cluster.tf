data "aws_region" "current" {}
resource "aws_eks_cluster" "this" {
  name     = var.name
  version  = var.kubernetes_version
  role_arn = var.role_arn
  # Control-plane logs only with an explicit retention (no unmanaged log group).
  enabled_cluster_log_types     = var.log_retention_days == null ? [] : ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  bootstrap_self_managed_addons = var.bootstrap_self_managed_addons
  deletion_protection           = var.deletion_protection
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }
  vpc_config {
    subnet_ids = var.subnet_ids
    # No additional SG: EKS creates and manages the cluster security group.
    endpoint_private_access = true
    endpoint_public_access  = false
  }
  # Customer KMS only when supplied; otherwise EKS default envelope encryption.
  dynamic "encryption_config" {
    for_each = var.kms_key_arn == null ? [] : [var.kms_key_arn]
    content {
      provider { key_arn = encryption_config.value }
      resources = ["secrets"]
    }
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
