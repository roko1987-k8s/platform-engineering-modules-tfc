output "pod_identity_association_id" {
  value = aws_eks_pod_identity_association.controller.association_id
}
output "service_account" {
  value = "${var.namespace}/${var.service_account}"
}
