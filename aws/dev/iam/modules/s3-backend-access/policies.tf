locals {
  # Read-only inspection: exactly the seven GET queries of stage 2 (no objects).
  inspect_actions = [
    "s3:GetBucketLocation", "s3:GetBucketOwnershipControls", "s3:GetBucketPolicy",
    "s3:GetBucketPublicAccessBlock", "s3:GetBucketTagging", "s3:GetBucketVersioning",
    "s3:GetEncryptionConfiguration",
  ]
  # Reviewed S3 module operations and AWS provider 6.20.0 metadata reads.
  # No bucket deletion, object access, ACL writes, IAM or EKS provisioning.
  bootstrap_actions = [
    "s3:CreateBucket", "s3:GetAccelerateConfiguration", "s3:GetBucketAcl",
    "s3:GetBucketCORS", "s3:GetBucketLocation", "s3:GetBucketLogging",
    "s3:GetBucketObjectLockConfiguration", "s3:GetBucketOwnershipControls",
    "s3:GetBucketPolicy", "s3:GetBucketPublicAccessBlock", "s3:GetBucketRequestPayment",
    "s3:GetBucketTagging", "s3:GetBucketVersioning", "s3:GetBucketWebsite",
    "s3:GetEncryptionConfiguration", "s3:GetLifecycleConfiguration", "s3:GetReplicationConfiguration",
    "s3:ListBucket", "s3:PutBucketOwnershipControls", "s3:PutBucketPolicy",
    "s3:PutBucketPublicAccessBlock", "s3:PutBucketTagging", "s3:PutBucketVersioning",
    "s3:PutEncryptionConfiguration",
  ]
  bucket_mutations = [
    "s3:CreateBucket", "s3:DeleteBucket", "s3:DeleteBucketPolicy", "s3:PutBucketAcl",
    "s3:PutBucketOwnershipControls", "s3:PutBucketPolicy", "s3:PutBucketPublicAccessBlock",
    "s3:PutBucketTagging", "s3:PutBucketVersioning", "s3:PutEncryptionConfiguration",
    "s3:PutLifecycleConfiguration", "s3:PutReplicationConfiguration",
  ]
  identity_escalation = [
    "iam:*", "sts:AssumeRole", "sts:AssumeRoleWithSAML", "sts:AssumeRoleWithWebIdentity",
    "ec2:*", "eks:*", "kms:*",
  ]
  # Every role: nothing outside its OWN bucket (and, for state roles, its own
  # State/lock objects); never bucket deletion, object versions or identity changes.
  common_denies = {
    no_bucket_only = [
      { Sid = "DenyOtherS3Resources", Effect = "Deny", Action = "s3:*", NotResource = local.bucket_arn },
      { Sid = "DenyDeletionAndEscalation", Effect = "Deny", Action = concat(["s3:DeleteBucket", "s3:DeleteObjectVersion", "s3:PutBucketAcl", "s3:PutObjectAcl"], local.identity_escalation), Resource = "*" },
    ]
    state = [
      { Sid = "DenyOtherS3Resources", Effect = "Deny", Action = "s3:*", NotResource = [local.bucket_arn, local.state_arn, local.lock_arn] },
      { Sid = "DenyBucketMutationAndEscalation", Effect = "Deny", Action = concat(local.bucket_mutations, ["s3:DeleteObjectVersion", "s3:PutObjectAcl"], local.identity_escalation), Resource = "*" },
    ]
  }
  state_reads = [
    { Sid = "BucketLocation", Effect = "Allow", Action = ["s3:GetBucketLocation"], Resource = local.bucket_arn },
    { Sid = "ListExactWorkspaceState", Effect = "Allow", Action = "s3:ListBucket", Resource = local.bucket_arn, Condition = { StringEquals = { "s3:prefix" = [local.state_key, local.lock_key] } } },
    # S3 native locking (use_lockfile = true): the lock of THIS State only. The
    # lock may only be CREATED with a conditional write (If-None-Match: *), never
    # overwritten; reading/releasing it does not grant any write on the State.
    { Sid = "ExactWorkspaceLockReadRelease", Effect = "Allow", Action = ["s3:DeleteObject", "s3:GetObject"], Resource = local.lock_arn },
    { Sid = "ExactWorkspaceLockCreate", Effect = "Allow", Action = "s3:PutObject", Resource = local.lock_arn, Condition = { StringEquals = { "s3:if-none-match" = "*" } } },
  ]
  policy_documents = {
    inspect = jsonencode({
      Version = "2012-10-17"
      Statement = concat([
        { Sid = "InspectOwnBucket", Effect = "Allow", Action = local.inspect_actions, Resource = local.bucket_arn },
      ], local.common_denies.no_bucket_only)
    })
    bootstrap = jsonencode({
      Version = "2012-10-17"
      Statement = concat([
        { Sid = "ConfigureOwnBucket", Effect = "Allow", Action = local.bootstrap_actions, Resource = local.bucket_arn, Condition = { StringEquals = { "aws:RequestedRegion" = var.backend.region } } },
      ], local.common_denies.no_bucket_only)
    })
    state_read = jsonencode({
      Version = "2012-10-17"
      Statement = concat(local.state_reads, [
        { Sid = "ReadExactWorkspaceState", Effect = "Allow", Action = ["s3:GetObject"], Resource = local.state_arn },
      ], local.common_denies.state)
    })
    state_write = jsonencode({
      Version = "2012-10-17"
      Statement = concat(local.state_reads, [
        { Sid = "WriteExactWorkspaceState", Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject"], Resource = local.state_arn },
      ], local.common_denies.state)
    })
  }
}
