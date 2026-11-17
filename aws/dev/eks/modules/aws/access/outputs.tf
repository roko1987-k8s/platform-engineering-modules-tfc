output "bot_role_arn" {
  description = "Read-only bot role of this cluster (assumed by the central bot identity)."
  value       = aws_iam_role.bot.arn
}

output "jump_instance_id" {
  description = "SSM jump host: target of AWS-StartPortForwardingSessionToRemoteHost."
  value       = aws_instance.jump.id
}

output "platform_admin_role_arns" {
  description = "Platform Engineering roles with cluster admin."
  value       = sort(keys(aws_eks_access_entry.platform))
}
