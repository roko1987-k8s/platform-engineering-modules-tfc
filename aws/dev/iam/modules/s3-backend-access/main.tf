resource "aws_iam_role" "this" {
  for_each             = local.operations
  name                 = local.role_names[each.key]
  path                 = local.role_paths[each.key]
  assume_role_policy   = local.trust_documents[each.key]
  permissions_boundary = var.foundation.boundary_arns[each.key]
  max_session_duration = 3600
  tags                 = merge(local.ownership_tags, { Operation = each.value, ApplicationCode = var.workspace.application_code })

  lifecycle {
    prevent_destroy = true
    precondition {
      condition     = var.workspace.team_id == var.authorized_team_id
      error_message = "The declared workspace must belong to the independently authorized team."
    }
    precondition {
      condition     = var.workspace.source.path == local.expected_path && local.workspace_id == format("eks-%02d", var.workspace.sequence)
      error_message = "Workspace path must match the verified team, cloud, environment and sequence."
    }
    precondition {
      condition     = var.workspace.region == var.backend.region && var.workspace.environment == var.backend.environment
      error_message = "The workspace region/environment must match the backend assignment context."
    }
    precondition {
      condition     = split(":", var.foundation.agent_principal_arn)[4] == var.backend.account_id
      error_message = "The approved technical principal must belong to the approved AWS account."
    }
    precondition {
      condition     = alltrue([for key in keys(local.operations) : var.foundation.boundary_arns[key] == local.boundary_arns[key]])
      error_message = "All four boundaries are mandatory and must be the foundation's per-operation ARNs in the approved account."
    }
    precondition {
      condition     = alltrue([for name in values(local.role_names) : length(name) <= 64])
      error_message = "Derived IAM names must fit AWS limits; never truncate names or fall back to a different naming rule."
    }
  }
}

resource "aws_iam_role_policy" "this" {
  for_each = local.operations
  name     = local.role_names[each.key]
  role     = aws_iam_role.this[each.key].name
  policy   = local.policy_documents[each.key]
  lifecycle {
    prevent_destroy = true
  }
}
