locals {
  naming_policy = jsondecode(file("${path.module}/../../../eks/naming/aws.json"))
  region_code   = lookup(local.naming_policy.region_codes, var.region, null)
  env_code      = lookup(local.naming_policy.environment_codes, var.environment, null)
  operations = {
    inspect     = "inspect"
    bootstrap   = "bootstrap"
    state_read  = "state-read"
    state_write = "state-write"
  }
  boundary_names = { for key, op in local.operations : key => "adp-s3-backend-${op}-boundary" }
  boundary_arns  = { for key, name in local.boundary_names : key => "arn:aws:iam::${var.account_id}:policy/adp/s3-backend/boundary/${name}" }

  # Ceilings shared by all workspaces of one operation, bound to EACH ROLE'S OWN
  # tags: the Bucket role tag (set at creation, never a session tag) and the
  # Team/Instance session tags (forced by the trust to equal the role's values).
  # A missing tag makes the variable unresolvable, so nothing matches.
  own_bucket = "arn:aws:s3:::$${aws:PrincipalTag/Bucket}"
  own_state  = "arn:aws:s3:::$${aws:PrincipalTag/Bucket}/states/$${aws:PrincipalTag/Team}/aws/${var.environment}/$${aws:PrincipalTag/Instance}/terraform.tfstate"
  own_lock   = "${local.own_state}.tflock"
  # Defence in depth: only names of the central workspace-bucket convention.
  # Unknown codes never produce a pattern (the boundary precondition fails first).
  bucket_pattern = "arn:aws:s3:::${local.naming_policy.resource_prefixes.s3}${coalesce(local.region_code, "-")}*${coalesce(local.env_code, "-")}??"

  boundary_allows = {
    inspect = [
      { Sid = "InspectOwnBucket", Effect = "Allow", Resource = local.own_bucket, Action = [
        "s3:GetBucketLocation", "s3:GetBucketOwnershipControls", "s3:GetBucketPolicy",
        "s3:GetBucketPublicAccessBlock", "s3:GetBucketTagging", "s3:GetBucketVersioning",
        "s3:GetEncryptionConfiguration",
      ] },
    ]
    bootstrap = [
      { Sid = "ConfigureOwnBucket", Effect = "Allow", Resource = local.own_bucket, Condition = { StringEquals = { "aws:RequestedRegion" = var.region } }, Action = [
        "s3:CreateBucket", "s3:GetAccelerateConfiguration", "s3:GetBucketAcl",
        "s3:GetBucketCORS", "s3:GetBucketLocation", "s3:GetBucketLogging",
        "s3:GetBucketObjectLockConfiguration", "s3:GetBucketOwnershipControls",
        "s3:GetBucketPolicy", "s3:GetBucketPublicAccessBlock", "s3:GetBucketRequestPayment",
        "s3:GetBucketTagging", "s3:GetBucketVersioning", "s3:GetBucketWebsite",
        "s3:GetEncryptionConfiguration", "s3:GetLifecycleConfiguration", "s3:GetReplicationConfiguration",
        "s3:ListBucket", "s3:PutBucketOwnershipControls", "s3:PutBucketPolicy",
        "s3:PutBucketPublicAccessBlock", "s3:PutBucketTagging", "s3:PutBucketVersioning",
        "s3:PutEncryptionConfiguration",
      ] },
    ]
    state_read = [
      { Sid = "OwnBucketList", Effect = "Allow", Action = ["s3:GetBucketLocation", "s3:ListBucket"], Resource = local.own_bucket },
      { Sid = "OwnStateRead", Effect = "Allow", Action = ["s3:GetObject"], Resource = local.own_state },
      { Sid = "OwnLockReadRelease", Effect = "Allow", Action = ["s3:DeleteObject", "s3:GetObject"], Resource = local.own_lock },
      { Sid = "OwnLockCreate", Effect = "Allow", Action = "s3:PutObject", Resource = local.own_lock, Condition = { StringEquals = { "s3:if-none-match" = "*" } } },
    ]
    state_write = [
      { Sid = "OwnBucketList", Effect = "Allow", Action = ["s3:GetBucketLocation", "s3:ListBucket"], Resource = local.own_bucket },
      { Sid = "OwnStateWrite", Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject"], Resource = local.own_state },
      { Sid = "OwnLockReadRelease", Effect = "Allow", Action = ["s3:DeleteObject", "s3:GetObject"], Resource = local.own_lock },
      { Sid = "OwnLockCreate", Effect = "Allow", Action = "s3:PutObject", Resource = local.own_lock, Condition = { StringEquals = { "s3:if-none-match" = "*" } } },
    ]
  }
  boundary_documents = {
    for key in keys(local.operations) : key => jsonencode({
      Version = "2012-10-17"
      Statement = concat(local.boundary_allows[key], [
        { Sid = "DenyOutsideWorkspaceBuckets", Effect = "Deny", Action = "s3:*", NotResource = [local.bucket_pattern, "${local.bucket_pattern}/states/*"] },
        { Sid = "DenyDeletion", Effect = "Deny", Action = ["s3:DeleteBucket", "s3:DeleteObjectVersion"], Resource = "*" },
        # Every session must carry SourceIdentity (CloudTrail attribution), even if
        # a role were created with a weaker trust than the reviewed one.
        { Sid = "RequireSourceIdentity", Effect = "Deny", Action = "*", Resource = "*", Condition = { Null = { "aws:SourceIdentity" = "true" } } },
      ])
    })
  }
}

resource "aws_iam_policy" "boundary" {
  for_each    = local.operations
  name        = local.boundary_names[each.key]
  path        = "/adp/s3-backend/boundary/"
  description = "Ceiling of every S3 backend ${each.value} role, bound to the role's own Bucket/Team/Instance tags."
  policy      = local.boundary_documents[each.key]
  tags        = { ManagedBy = "Terraform", Ownership = "s3-backend-foundation", Operation = each.value }

  lifecycle {
    prevent_destroy = true
    precondition {
      condition     = local.region_code != null && local.env_code != null
      error_message = "Region and environment must exist in the central naming policy."
    }
    precondition {
      condition     = split(":", var.agent_principal_arn)[4] == var.account_id
      error_message = "The approved technical principal must belong to the approved AWS account."
    }
  }
}
