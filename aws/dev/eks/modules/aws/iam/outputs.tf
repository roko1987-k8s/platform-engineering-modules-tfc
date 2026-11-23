output "cluster_role_arn" {
  value      = aws_iam_role.cluster.arn
  depends_on = [aws_iam_role_policy_attachment.cluster]
}
output "node_role_arns" {
  value      = { for k, r in aws_iam_role.nodes : k => r.arn }
  depends_on = [aws_iam_role_policy_attachment.nodes]
}
output "pod_identity_role_arns" {
  value      = { for k, r in aws_iam_role.pod_identity : k => r.arn }
  depends_on = [aws_iam_role_policy.pod_identity]
}
output "lb_controller_role_arn" {
  value      = var.lb_controller ? aws_iam_role.lb_controller[0].arn : null
  depends_on = [aws_iam_role_policy.lb_controller]
}
