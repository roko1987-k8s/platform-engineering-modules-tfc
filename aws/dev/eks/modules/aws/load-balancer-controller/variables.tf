variable "cluster_name" {
  type = string
}
variable "kubernetes_version" {
  type = string
}
variable "role_arn" {
  description = "Controller role from modules/aws/iam (lb_controller_role_arn)."
  type        = string
}
variable "namespace" {
  description = "Namespace of the controller's service account: its own, never kube-system (the Argo CD project of the tools cannot deploy there)."
  type        = string
  default     = "aws-load-balancer-controller"
}
variable "service_account" {
  description = "Service account of the controller (Helm chart default)."
  type        = string
  default     = "aws-load-balancer-controller"
}
variable "tags" {
  type = map(string)
}
