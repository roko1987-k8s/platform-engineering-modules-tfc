locals {
  control_name  = "adp-s3-backend-control"
  control_arn   = "arn:aws:iam::${var.account_id}:role/adp/control/${local.control_name}"
  role_ns       = "arn:aws:iam::${var.account_id}:role/adp/s3-backend/*"
  boundary_ns   = "arn:aws:iam::${var.account_id}:policy/adp/s3-backend/boundary/*"
  identity_tags = ["Team", "Instance", "Bucket", "Operation"]
  # <s3 prefix><region code><4-char team><env code><NN>, e.g. names.s3 of a workspace.
  bucket_tag_pattern = "${local.naming_policy.resource_prefixes.s3}${coalesce(local.region_code, "-")}????${coalesce(local.env_code, "-")}??"
  role_tag_keys      = ["ManagedBy", "Ownership", "Team", "Instance", "Bucket", "Environment", "Operation", "ApplicationCode"]

  # Same IAM semantics as the workspace roles (see s3-backend-access/trust.tf):
  # SourceIdentity with SetSourceIdentity; the Operation tag in TagSession and made
  # mandatory with explicit Deny statements on AssumeRole.
  control_trust = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AssumeWithSourceIdentity"
        Effect    = "Allow"
        Principal = { AWS = var.agent_principal_arn }
        Action    = ["sts:AssumeRole", "sts:SetSourceIdentity"]
        # Only sts:SourceIdentity (also evaluated for sts:SetSourceIdentity).
        Condition = { Null = { "sts:SourceIdentity" = "false" } }
      },
      {
        Sid       = "RequireSessionName"
        Effect    = "Deny"
        Principal = { AWS = var.agent_principal_arn }
        Action    = "sts:AssumeRole"
        Condition = { StringNotLike = { "sts:RoleSessionName" = "adp-s3-backend-control*" } }
      },
      {
        Sid       = "TagControlSession"
        Effect    = "Allow"
        Principal = { AWS = var.agent_principal_arn }
        Action    = "sts:TagSession"
        Condition = {
          StringEquals                = { "aws:RequestTag/Operation" = "s3-backend-control" }
          "ForAllValues:StringEquals" = { "aws:TagKeys" = ["Operation"] }
          Null                        = { "aws:RequestTag/Operation" = "false", "sts:TransitiveTagKeys" = "true" }
        }
      },
      {
        Sid       = "DenyTransitiveTags"
        Effect    = "Deny"
        Principal = { AWS = var.agent_principal_arn }
        Action    = ["sts:AssumeRole", "sts:TagSession"]
        Condition = { Null = { "sts:TransitiveTagKeys" = "false" } }
      },
      {
        Sid       = "RequireOperationTag"
        Effect    = "Deny"
        Principal = { AWS = var.agent_principal_arn }
        Action    = "sts:AssumeRole"
        Condition = { StringNotEquals = { "aws:RequestTag/Operation" = "s3-backend-control" } }
      },
    ]
  })

  # Create/configure ONLY the namespaced workspace roles, each with the exact
  # boundary of its operation; never itself, the boundaries, Python executor
  # roles (/adp/executor/), EKS roles or any other IAM resource.
  control_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        { Sid = "ReadWorkspaceRoles", Effect = "Allow", Resource = local.role_ns, Action = [
          "iam:GetRole", "iam:GetRolePolicy", "iam:ListAttachedRolePolicies",
          "iam:ListInstanceProfilesForRole", "iam:ListRolePolicies", "iam:ListRoleTags",
        ] },
        { Sid = "ReadBoundaries", Effect = "Allow", Action = ["iam:GetPolicy", "iam:GetPolicyVersion"], Resource = local.boundary_ns },
      ],
      flatten([for key, op in local.operations : [
        {
          Sid      = "Create${replace(title(replace(op, "-", " ")), " ", "")}Role"
          Effect   = "Allow"
          Action   = "iam:CreateRole"
          Resource = "arn:aws:iam::${var.account_id}:role/adp/s3-backend/${op}/*-s3backend-${op}"
          Condition = {
            ArnEquals    = { "iam:PermissionsBoundary" = local.boundary_arns[key] }
            StringEquals = { "aws:RequestTag/ManagedBy" = "Terraform", "aws:RequestTag/Ownership" = "s3-backend-access", "aws:RequestTag/Operation" = op }
            Null         = { "aws:RequestTag/Team" = "false", "aws:RequestTag/Instance" = "false", "aws:RequestTag/Bucket" = "false" }
            # Shape only: IAM cannot tie the Bucket tag to the role name (TD-022).
            StringLike                  = { "aws:RequestTag/Team" = ["D???", "P???"], "aws:RequestTag/Instance" = "eks-??", "aws:RequestTag/Bucket" = local.bucket_tag_pattern }
            "ForAllValues:StringEquals" = { "aws:TagKeys" = local.role_tag_keys }
          }
        },
        {
          Sid       = "Bound${replace(title(replace(op, "-", " ")), " ", "")}Role"
          Effect    = "Allow"
          Action    = "iam:PutRolePermissionsBoundary"
          Resource  = "arn:aws:iam::${var.account_id}:role/adp/s3-backend/${op}/*-s3backend-${op}"
          Condition = { ArnEquals = { "iam:PermissionsBoundary" = local.boundary_arns[key] } }
        },
        {
          Sid       = "Configure${replace(title(replace(op, "-", " ")), " ", "")}Role"
          Effect    = "Allow"
          Action    = ["iam:PutRolePolicy", "iam:TagRole"]
          Resource  = "arn:aws:iam::${var.account_id}:role/adp/s3-backend/${op}/*-s3backend-${op}"
          Condition = { "ForAllValues:StringEquals" = { "aws:TagKeys" = local.role_tag_keys } }
        },
      ]]),
      [
        # Identity tags are written once at creation; never moved to another bucket.
        { Sid = "NeverRetagIdentity", Effect = "Deny", Action = "iam:TagRole", Resource = "*", Condition = { "ForAnyValue:StringEquals" = { "aws:TagKeys" = local.identity_tags }, Null = { "aws:ResourceTag/Bucket" = "false" } } },
        { Sid = "NeverWeakenOrRemove", Effect = "Deny", Resource = "*", Action = [
          "iam:AttachRolePolicy", "iam:CreatePolicy", "iam:CreatePolicyVersion", "iam:DeletePolicy",
          "iam:DeletePolicyVersion", "iam:DeleteRole", "iam:DeleteRolePermissionsBoundary",
          "iam:DeleteRolePolicy", "iam:DetachRolePolicy", "iam:SetDefaultPolicyVersion",
          "iam:UntagRole", "iam:UpdateAssumeRolePolicy", "iam:UpdateRole",
        ] },
        { Sid = "NoUsersKeysOrPassRole", Effect = "Deny", Resource = "*", Action = [
          "iam:AttachUserPolicy", "iam:CreateAccessKey", "iam:CreateLoginProfile", "iam:CreateUser",
          "iam:PassRole", "iam:PutUserPolicy", "iam:UpdateAccessKey",
        ] },
        { Sid = "OnlyTheWorkspaceNamespace", Effect = "Deny", Action = "iam:*", NotResource = [local.role_ns, local.boundary_ns] },
        { Sid = "NoDataPlaneOrChaining", Effect = "Deny", Resource = "*", Action = ["s3:*", "ec2:*", "eks:*", "kms:*", "sts:AssumeRole", "sts:AssumeRoleWithSAML", "sts:AssumeRoleWithWebIdentity"] },
      ]
    )
  })

  # Identity-side permissions adp-agent-dev will need once AdministratorAccess is
  # removed. Output only: this module never attaches anything to the user.
  agent_identity_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AssumeS3BackendRoles"
      Effect   = "Allow"
      Action   = ["sts:AssumeRole", "sts:SetSourceIdentity", "sts:TagSession"]
      Resource = [local.control_arn, local.role_ns]
    }]
  })
}

resource "aws_iam_role" "control" {
  name                 = local.control_name
  path                 = "/adp/control/"
  assume_role_policy   = local.control_trust
  max_session_duration = 3600
  tags                 = { ManagedBy = "Terraform", Ownership = "s3-backend-foundation", Operation = "s3-backend-control" }
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role_policy" "control" {
  name   = local.control_name
  role   = aws_iam_role.control.name
  policy = local.control_policy
  lifecycle {
    prevent_destroy = true
  }
}
