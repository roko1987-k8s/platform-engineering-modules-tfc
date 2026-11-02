output "role_arns" {
  description = "Role ARNs keyed by plan/apply/destroy for future reviewed workflow configuration."
  value       = { for phase, role in aws_iam_role.phase : phase => role.arn }
}

output "role_names" {
  description = "Approved role names keyed by phase."
  value       = { for phase, role in aws_iam_role.phase : phase => role.name }
}

output "trust_policies" {
  description = "Rendered exact-match trust policies for review."
  value       = local.trust_policies
}

output "backend_policy" {
  description = "Scoped backend policy document; attached only to explicitly opted-in phases."
  value       = local.backend_policy
}

output "state_key" {
  description = "Exact state key for the authorized team/environment/instance."
  value       = local.state_key
}

output "provisioning_enabled" {
  description = "Always false: no provisioning permissions are defined or attached by this module."
  value       = false
}
