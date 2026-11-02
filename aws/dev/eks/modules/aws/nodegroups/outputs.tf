output "groups" {
  value = { for role, group in aws_eks_node_group.role : role => { arn = group.arn, id = group.id, instance_type = var.catalog.nodegroups[role].sizes[var.selections[role].size], security_group_id = var.security_group_ids[role], launch_template_id = aws_launch_template.role[role].id, release_version = group.release_version } }
}
