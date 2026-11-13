locals {
  # Only adp-agent-dev may assume a workspace role, and only with:
  # - a SourceIdentity (verified employeeId, visible in CloudTrail) and this
  #   workspace's session name (adp-<TEAM>-<eks-NN>-<operation>, as built by the
  #   agent's AssumeRole helper);
  # - exactly the session tags Team, Instance (eks-NN) and Operation, never others
  #   and never transitive.
  # IAM semantics: sts:SourceIdentity must be granted together with
  # sts:SetSourceIdentity, and aws:RequestTag/* is not supported for that action,
  # so tags are allowed in a separate TagSession statement and made mandatory
  # with explicit Deny statements on AssumeRole (missing or different value).
  session_tags = { for key, op in local.operations : key => {
    Team      = var.authorized_team_id
    Instance  = local.workspace_id
    Operation = op
  } }
  trust_documents = {
    for key, op in local.operations : key => jsonencode({
      Version = "2012-10-17"
      Statement = concat(
        [
          {
            Sid       = "AssumeWithSourceIdentity"
            Effect    = "Allow"
            Principal = { AWS = var.foundation.agent_principal_arn }
            Action    = ["sts:AssumeRole", "sts:SetSourceIdentity"]
            Condition = {
              Null       = { "sts:SourceIdentity" = "false" }
              StringLike = { "sts:RoleSessionName" = "adp-${var.authorized_team_id}-${local.workspace_id}-${op}*" }
            }
          },
          {
            Sid       = "TagWorkspaceSession"
            Effect    = "Allow"
            Principal = { AWS = var.foundation.agent_principal_arn }
            Action    = "sts:TagSession"
            Condition = {
              StringEquals                = { for tag, value in local.session_tags[key] : "aws:RequestTag/${tag}" => value }
              "ForAllValues:StringEquals" = { "aws:TagKeys" = ["Team", "Instance", "Operation"] }
              Null = merge(
                { for tag in keys(local.session_tags[key]) : "aws:RequestTag/${tag}" => "false" },
                { "sts:TransitiveTagKeys" = "true" }
              )
            }
          },
          {
            Sid       = "DenyTransitiveTags"
            Effect    = "Deny"
            Principal = { AWS = var.foundation.agent_principal_arn }
            Action    = ["sts:AssumeRole", "sts:TagSession"]
            Condition = { Null = { "sts:TransitiveTagKeys" = "false" } }
          },
        ],
        [for tag, value in local.session_tags[key] : {
          Sid       = "Require${tag}Tag"
          Effect    = "Deny"
          Principal = { AWS = var.foundation.agent_principal_arn }
          Action    = "sts:AssumeRole"
          Condition = { StringNotEquals = { "aws:RequestTag/${tag}" = value } }
        }]
      )
    })
  }
}
