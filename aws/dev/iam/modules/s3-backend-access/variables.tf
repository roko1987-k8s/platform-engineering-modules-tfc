variable "authorized_team_id" {
  description = "Team already authenticated and authorized by the caller backend. Terraform cannot verify Keycloak or confer this authorization."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[DP]([0-9]{2}[1-9]|[0-9][1-9][0-9]|[1-9][0-9]{2})$", var.authorized_team_id))
    error_message = "Supply the canonical, backend-authorized team; zero team codes are forbidden."
  }
}

variable "workspace" {
  description = "ONE authorized GP01 workspace (eks-NN), extracted at an immutable source.commit without evaluating Terraform. One invocation owns only the four backend roles of that workspace's bucket."
  type = object({
    id               = string
    team_id          = string
    application_code = string
    environment      = string
    region           = string
    sequence         = number
    source           = object({ repository = string, commit = string, path = string })
  })
  nullable = false
  validation {
    condition     = can(regex("^eks-[0-9]{2}$", var.workspace.id)) && can(regex("^[DP][0-9]{3}$", var.workspace.team_id)) && can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,39}$", var.workspace.application_code))
    error_message = "Supply canonical declared workspace, team and application values from GP01."
  }
  validation {
    condition     = var.workspace.sequence >= 1 && var.workspace.sequence <= 99 && floor(var.workspace.sequence) == var.workspace.sequence
    error_message = "Workspace sequence must be an integer between 1 and 99."
  }
  validation {
    condition     = var.workspace.source.repository == "roko1987-k8s/platform-engineering-devs" && can(regex("^[a-f0-9]{40}$", var.workspace.source.commit))
    error_message = "Supply the approved workspace repository and a full immutable commit, never a branch or URL."
  }
}

variable "backend" {
  description = "Server-side assignment context of the workspace bucket. The bucket name is DERIVED from the central naming with the instance sequence; it is never supplied."
  type = object({
    account_id          = string
    region              = string
    environment         = string
    assignment_revision = string
    approval_reference  = string
  })
  nullable = false
  validation {
    condition     = can(regex("^[0-9]{12}$", var.backend.account_id))
    error_message = "Supply the exact approved AWS account."
  }
  validation {
    condition     = can(regex("^[a-f0-9]{64}$", var.backend.assignment_revision)) && can(regex("^\\S{1,256}$", var.backend.approval_reference))
    error_message = "Backend assignment requires a content revision and a nonempty approval reference."
  }
}

variable "foundation" {
  description = "Operator-owned foundation evidence. The four operation boundaries must already exist (s3-backend-foundation state); this module never creates its own authority."
  type = object({
    agent_principal_arn = string
    boundary_arns       = object({ inspect = string, bootstrap = string, state_read = string, state_write = string })
    revision            = string
    approval_reference  = string
  })
  nullable = false
  validation {
    # adp-agent-dev is the only approved technical source identity.
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:user/adp-agent-dev$", var.foundation.agent_principal_arn))
    error_message = "Trust exactly the IAM user adp-agent-dev; roles, root, STS sessions, federation, wildcards and lists are forbidden."
  }
  validation {
    condition     = can(regex("^[a-f0-9]{64}$", var.foundation.revision)) && can(regex("^\\S{1,256}$", var.foundation.approval_reference))
    error_message = "Foundation requires an externally approved revision and approval reference."
  }
}

# A foundation revision is evidence checked by the caller, not a self-issued grant.
