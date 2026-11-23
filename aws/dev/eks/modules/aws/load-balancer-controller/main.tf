# What the AWS Load Balancer Controller needs from AWS before the tools install it:
# the EKS Pod Identity agent (managed add-on) and the association of its service account
# with the role created by modules/aws/iam. The controller itself (Helm chart) is a
# platform tool installed by Argo CD from platform-engineering-tools.
data "aws_eks_addon_version" "pod_identity_agent" {
  addon_name         = "eks-pod-identity-agent"
  kubernetes_version = var.kubernetes_version
  most_recent        = false # default version for this Kubernetes version
}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name                = var.cluster_name
  addon_name                  = "eks-pod-identity-agent"
  addon_version               = data.aws_eks_addon_version.pod_identity_agent.version
  resolve_conflicts_on_create = "NONE"
  resolve_conflicts_on_update = "NONE"
  tags                        = var.tags
}

resource "aws_eks_pod_identity_association" "controller" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account
  role_arn        = var.role_arn
  tags            = var.tags
  depends_on      = [aws_eks_addon.pod_identity_agent]
}
