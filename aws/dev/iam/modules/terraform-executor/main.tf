# Execution identities for the Terraform Agent. Vault assumes one role per
# operation and attaches a per-team session policy; there are no IAM users,
# access keys or per-team roles here.

data "aws_partition" "current" {}

locals {
  partition = data.aws_partition.current.partition
  trust = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = var.vault_principal_arn }
      Action    = "sts:AssumeRole"
    }]
  })

  # Backend key shape of the agent registry: states/{cloud}/{environment}/{deployment}/terraform.tfstate.
  # Same actions as state.json in github-oidc; the Vault session policy narrows each
  # credential to one bucket and one key.
  state_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "StateList"
        Effect    = "Allow"
        Action    = ["s3:ListBucket"]
        Resource  = [for b in sort(tolist(var.state_buckets)) : "arn:${local.partition}:s3:::${b}"]
        Condition = { StringLike = { "s3:prefix" = ["states/aws/*"] } }
      },
      {
        Sid      = "StateObject"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = [for b in sort(tolist(var.state_buckets)) : "arn:${local.partition}:s3:::${b}/states/aws/*/terraform.tfstate"]
      },
      {
        Sid      = "StateLock"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = [for b in sort(tolist(var.state_buckets)) : "arn:${local.partition}:s3:::${b}/states/aws/*/terraform.tfstate.tflock"]
      },
    ]
  })

  # Reviewed policy sources; each statement is pinned to the catalog region.
  region_condition = { StringEquals = { "aws:RequestedRegion" = var.region } }
  phase_documents = {
    plan    = ["networking-read.json"]
    apply   = ["networking-read.json", "networking-apply.json"]
    destroy = ["networking-read.json", "networking-destroy.json"]
  }
  provisioning_policies = {
    for phase, files in local.phase_documents : phase => jsonencode({
      Version = "2012-10-17"
      Statement = flatten([
        for f in files : [
          for s in jsondecode(file("${path.module}/${f}")).Statement : merge(s, { Condition = local.region_condition })
        ]
      ])
    })
  }
}

resource "aws_iam_role" "phase" {
  for_each             = var.roles
  name                 = each.value.name
  assume_role_policy   = local.trust
  max_session_duration = 3600
  tags                 = merge(var.tags, { Operation = each.key })
}

resource "aws_iam_role_policy" "state" {
  for_each = var.roles
  name     = "${each.key}-state-backend"
  role     = aws_iam_role.phase[each.key].name
  policy   = local.state_policy
}

# Not attached until the phase is explicitly opted in after review.
resource "aws_iam_role_policy" "networking" {
  for_each = var.provisioning_phases
  name     = "${each.key}-networking"
  role     = aws_iam_role.phase[each.key].name
  policy   = local.provisioning_policies[each.key]
}
