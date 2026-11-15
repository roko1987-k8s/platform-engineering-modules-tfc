resource "aws_eks_node_group" "role" {
  for_each        = var.selections
  cluster_name    = var.cluster_name
  node_group_name = "${var.cluster_name}-${each.key}"
  node_role_arn   = var.node_role_arns[each.key]
  subnet_ids      = var.subnet_ids
  version         = var.kubernetes_version
  ami_type        = "AL2023_x86_64_STANDARD"
  release_version = each.value.release_version
  instance_types  = [var.catalog.nodegroups[each.key].sizes[each.value.size]]
  capacity_type   = each.value.capacity_type
  scaling_config {
    min_size     = each.value.minimum
    desired_size = each.value.desired
    max_size     = each.value.maximum
  }
  launch_template {
    id      = aws_launch_template.role[each.key].id
    version = tostring(aws_launch_template.role[each.key].latest_version)
  }
  update_config { max_unavailable = 1 }
  labels = { "platform.example/node-role" = each.key }
  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }
  tags = merge(var.tags, { NodeRole = each.key })
}
