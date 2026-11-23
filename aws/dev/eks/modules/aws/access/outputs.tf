output "bot_role_arn" {
  description = "Read-only bot role of this cluster (assumed by the central bot identity)."
  value       = aws_iam_role.bot.arn
}

output "tools_role_arn" {
  description = "Tools role of this cluster (cluster admin for the Argo CD bootstrap; assumed by the tools broker)."
  value       = aws_iam_role.tools.arn
}

output "jump_security_group_id" {
  description = "SSM jump host security group (egress to the internal NLB is added by security-groups)."
  value       = aws_security_group.jump.id
}

output "jump_instance_id" {
  description = "SSM jump host: target of AWS-StartPortForwardingSessionToRemoteHost."
  value       = aws_instance.jump.id
}

output "platform_admin_role_arns" {
  description = "Platform Engineering roles with cluster admin."
  value       = sort(keys(aws_eks_access_entry.platform))
}

output "cleanup_role_arn" {
  description = "Cleanup role of this cluster (Destroy pre-step, assumed through adp-k8s-cleanup-broker)."
  value       = aws_iam_role.cleanup.arn
}
