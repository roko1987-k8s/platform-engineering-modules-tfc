locals {
  # Preserve and reuse the original reviewed documents as the sole policy sources.
  trust_template = jsondecode(file("${path.module}/trust.json.template"))
  bucket_arn     = "arn:${split(":", var.oidc_provider_arn)[1]}:s3:::${var.state_scope.bucket_name}"
  state_key      = "states/${var.state_scope.team_id}/aws/${var.state_scope.environment}/${var.state_scope.instance}/terraform.tfstate"
  backend_policy = jsonencode(jsondecode(replace(replace(
    file("${path.module}/state.json"),
    "arn:aws:s3:::s3ue1p001dev01", local.bucket_arn),
    "states/D001/aws/dev/eks-01/terraform.tfstate", local.state_key
  )))
  trust_policies = {
    for phase, role in var.roles : phase => jsonencode(merge(local.trust_template, {
      Statement = [merge(one(local.trust_template.Statement), {
        Principal = { Federated = var.oidc_provider_arn }
        Condition = {
          StringEquals = merge(one(local.trust_template.Statement).Condition.StringEquals, {
            "token.actions.githubusercontent.com:sub"                 = role.subject
            "token.actions.githubusercontent.com:repository"          = var.executor_repository
            "token.actions.githubusercontent.com:repository_id"       = var.executor_repository_id
            "token.actions.githubusercontent.com:repository_owner_id" = var.executor_owner_id
            "token.actions.githubusercontent.com:ref"                 = role.ref
            "token.actions.githubusercontent.com:environment"         = role.environment
            }, role.job_workflow_ref == null ? {} : {
            "token.actions.githubusercontent.com:job_workflow_ref" = role.job_workflow_ref
          })
        }
      })]
    }))
  }
}

resource "aws_iam_role" "phase" {
  for_each = var.roles

  name               = each.value.name
  assume_role_policy = local.trust_policies[each.key]
}

# Backend permissions are separate from provisioning. No provisioning policy is
# accepted or attached until its actual permissions have been explicitly reviewed.
resource "aws_iam_role_policy" "backend" {
  for_each = var.backend_access_phases

  name   = "${each.key}-state-backend"
  role   = aws_iam_role.phase[each.key].name
  policy = local.backend_policy
}
