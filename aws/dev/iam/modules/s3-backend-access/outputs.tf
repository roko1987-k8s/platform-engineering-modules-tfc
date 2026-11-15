output "resolved" {
  description = "Derived proposals, not proof of AWS existence, ownership or an approved binding."
  value = {
    team_id             = var.authorized_team_id
    workspace_id        = local.workspace_id
    workspace_path      = local.expected_path
    workspace_commit    = var.workspace.source.commit
    bucket              = local.bucket
    state_key           = local.state_key
    lock_key            = local.lock_key
    assignment_revision = var.backend.assignment_revision
    role_names          = local.role_names
    role_paths          = local.role_paths
  }
}

output "role_arns" {
  description = "Actual provider ARNs, no credentials. These S3-only roles never replace EKS provisioning credentials."
  value       = { for key in keys(local.operations) : key => aws_iam_role.this[key].arn }
}

output "policies" {
  description = "Inline policies indexed by operation, for review rather than proof of effective permissions."
  value       = local.policy_documents
}

output "trust_policies" {
  description = "Trust policies indexed by operation, for review."
  value       = local.trust_documents
}

output "foundation_requirements" {
  description = "Boundary ARNs this workspace expects from the independent foundation. ARN equality does not verify deployed boundary contents."
  value       = local.boundary_arns
}
