output "role_arns" {
  description = "Role ARNs keyed by plan/apply/destroy, for the Vault AWS secrets engine roles."
  value       = { for phase, role in aws_iam_role.phase : phase => role.arn }
}
output "state_policy" {
  value = local.state_policy
}
output "provisioning_policies" {
  description = "Rendered networking policies per phase (attached only to opted-in phases)."
  value       = local.provisioning_policies
}
output "provisioning_enabled" {
  value = { for phase in ["plan", "apply", "destroy"] : phase => contains(var.provisioning_phases, phase) }
}
