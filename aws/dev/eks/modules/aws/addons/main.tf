# Foundational add-ons can precede nodes. CoreDNS follows nodes in composition.
resource "aws_eks_addon" "managed" {
  for_each                    = { for name, addon in var.addons : name => addon if name != "eks-pod-identity-agent" }
  cluster_name                = var.cluster_name
  addon_name                  = each.key
  addon_version               = each.value.version
  configuration_values        = each.value.configuration_values
  service_account_role_arn    = each.value.service_account_role_arn
  resolve_conflicts_on_create = "NONE"
  resolve_conflicts_on_update = "NONE"
  preserve                    = true
  dynamic "pod_identity_association" {
    for_each = each.value.pod_identity_associations
    content {
      service_account = pod_identity_association.key
      role_arn        = pod_identity_association.value
    }
  }
  tags       = var.tags
  depends_on = [aws_eks_addon.identity_agent]
}

# Create the identity agent before any managed add-on association relies on it.
resource "aws_eks_addon" "identity_agent" {
  for_each                    = { for name, addon in var.addons : name => addon if name == "eks-pod-identity-agent" }
  cluster_name                = var.cluster_name
  addon_name                  = each.key
  addon_version               = each.value.version
  configuration_values        = each.value.configuration_values
  resolve_conflicts_on_create = "NONE"
  resolve_conflicts_on_update = "NONE"
  preserve                    = true
  tags                        = var.tags
}
