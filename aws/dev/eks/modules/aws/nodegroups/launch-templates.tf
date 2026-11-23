resource "aws_launch_template" "role" {
  for_each    = var.selections
  name_prefix = "${var.cluster_name}-${each.key}-"
  # Own node group (modules/aws/security-groups): with a group set here EKS no longer
  # attaches its cluster security group to the nodes; rules 100/101 replace it.
  vpc_security_group_ids = [var.node_security_group_ids[each.key]]
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      encrypted = true
      # null: AWS managed EBS key and the AMI's root volume size.
      kms_key_id            = try(var.root_volumes[each.key].kms_key_arn, null)
      volume_size           = try(var.root_volumes[each.key].size_gib, null)
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }
  # No AMI ID, instance type, user_data, instance profile or subnet here.
  # EKS supplies AL2023 bootstrap data for the managed AMI selected below.
  tag_specifications {
    resource_type = "instance"
    # Without AdpInstance: adding it here would create a new launch template version
    # and roll every node; EKS (not the executor role) launches these instances.
    tags = merge({ for k, v in var.tags : k => v if k != "AdpInstance" }, { Name = "${var.cluster_name}-${each.key}", NodeRole = each.key })
  }
  tags = var.tags
}
