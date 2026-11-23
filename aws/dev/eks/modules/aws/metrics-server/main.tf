# Metrics Server as an EKS managed (community) add-on: resource metrics for the HPAs of the
# platform tools (istiod, Istio gateway). Without it an HPA has no metrics, Argo CD reports it
# Degraded and the following sync waves never run (D010 2026-11-22). Here and not as a tool:
# it lives in kube-system, where the tools' Argo CD project never deploys. AKS ships it.
data "aws_eks_addon_version" "metrics_server" {
  addon_name         = "metrics-server"
  kubernetes_version = var.kubernetes_version
  most_recent        = false # default version for this Kubernetes version
}

resource "aws_eks_addon" "metrics_server" {
  cluster_name                = var.cluster_name
  addon_name                  = "metrics-server"
  addon_version               = data.aws_eks_addon_version.metrics_server.version
  resolve_conflicts_on_create = "NONE"
  resolve_conflicts_on_update = "NONE"
  tags                        = var.tags
}
