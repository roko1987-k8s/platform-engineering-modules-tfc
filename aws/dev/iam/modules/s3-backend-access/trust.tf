locals {
  # Only adp-agent-dev, with this workspace's session name, the three session tags
  # (Team, Instance=eks-NN, Operation), a mandatory SourceIdentity (verified
  # employeeId, visible in CloudTrail) and no transitive tags. Session name as built
  # by the agent's AssumeRole helper: adp-<TEAM>-<eks-NN>-<operation>.
  trust_documents = {
    for key, op in local.operations : key => jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid       = "AdpAgentWorkspaceSession"
        Effect    = "Allow"
        Principal = { AWS = var.foundation.agent_principal_arn }
        Action    = ["sts:AssumeRole", "sts:TagSession", "sts:SetSourceIdentity"]
        Condition = {
          StringEquals = {
            "aws:RequestTag/Team"      = var.authorized_team_id
            "aws:RequestTag/Instance"  = local.workspace_id
            "aws:RequestTag/Operation" = op
          }
          "ForAllValues:StringEquals" = { "aws:TagKeys" = ["Team", "Instance", "Operation"] }
          Null = {
            "sts:SourceIdentity"       = "false"
            "aws:RequestTag/Team"      = "false"
            "aws:RequestTag/Instance"  = "false"
            "aws:RequestTag/Operation" = "false"
            "sts:TransitiveTagKeys"    = "true"
          }
          StringLike = { "sts:RoleSessionName" = "adp-${var.authorized_team_id}-${local.workspace_id}-${op}*" }
        }
      }]
    })
  }
}
