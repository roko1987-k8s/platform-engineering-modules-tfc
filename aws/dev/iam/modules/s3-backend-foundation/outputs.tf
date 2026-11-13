output "boundary_arns" {
  description = "Per-operation boundary ARNs to pass to every s3-backend-access invocation."
  value       = { for key in keys(local.operations) : key => aws_iam_policy.boundary[key].arn }
}

output "boundaries" {
  description = "Boundary documents and SHA-256 for independent review."
  value       = { for key in keys(local.operations) : key => { arn = local.boundary_arns[key], document = local.boundary_documents[key], sha256 = sha256(local.boundary_documents[key]) } }
}

output "control" {
  description = "Control role ARN, trust and inline policy for review. No credentials."
  value       = { arn = aws_iam_role.control.arn, trust = local.control_trust, policy = local.control_policy }
}

output "agent_identity_policy" {
  description = "Identity-side STS document for adp-agent-dev. NOT attached by this module; attaching it (and removing AdministratorAccess) is a separate authorized step."
  value       = local.agent_identity_policy
}
