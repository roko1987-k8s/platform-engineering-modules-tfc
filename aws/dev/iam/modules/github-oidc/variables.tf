variable "oidc_provider_arn" {
  description = "Explicit ARN of an existing GitHub OIDC provider in the target account. This module never manages it."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^arn:aws(-[a-z-]+)?:iam::[0-9]{12}:oidc-provider/token\\.actions\\.githubusercontent\\.com$", var.oidc_provider_arn))
    error_message = "Supply the exact existing GitHub OIDC provider ARN, without wildcards."
  }
}

variable "executor_repository" {
  description = "GitHub OWNER/REPOSITORY that executes workflows, independent of the module repository."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+$", var.executor_repository))
    error_message = "Supply one exact executor OWNER/REPOSITORY."
  }
}

variable "executor_repository_id" {
  description = "Verified immutable ID of the executor repository."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[0-9]+$", var.executor_repository_id))
    error_message = "Supply the verified numeric repository ID."
  }
}

variable "executor_owner_id" {
  description = "Verified immutable ID of the executor repository owner."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[0-9]+$", var.executor_owner_id))
    error_message = "Supply the verified numeric owner ID."
  }
}

variable "roles" {
  description = "Exactly plan/apply/destroy with approved names, distinct environments and verified subjects. No Validate role."
  type = map(object({
    name        = string
    subject     = string
    ref         = string
    environment = string
    # Optional additional restriction for a verified reusable workflow only.
    job_workflow_ref = optional(string)
  }))
  nullable = false
  validation {
    condition     = toset(keys(var.roles)) == toset(["plan", "apply", "destroy"])
    error_message = "Define exactly plan, apply and destroy; Validate must not have an AWS role."
  }
  validation {
    condition = alltrue([for role in var.roles :
      can(regex("^[A-Za-z0-9_+=,.@-]{1,64}$", role.name)) &&
      can(regex("^refs/heads/[^*?[:space:]]+$", role.ref)) &&
      can(regex("^[A-Za-z0-9_.-]+$", role.environment)) &&
      (role.job_workflow_ref == null ? true : can(regex("^[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+/\\.github/workflows/[^*?[:space:]]+@[^*?[:space:]]+$", role.job_workflow_ref)))
    ])
    error_message = "Use exact role names, branch refs, environments and optional reusable-workflow refs without wildcards."
  }
  validation {
    condition     = length(distinct([for role in var.roles : lower(role.name)])) == 3 && length(distinct([for role in var.roles : role.environment])) == 3
    error_message = "All three role names and environments must be distinct."
  }
  validation {
    condition = alltrue([for role in var.roles : contains([
      "repo:${var.executor_repository}:environment:${role.environment}",
      "repo:${split("/", var.executor_repository)[0]}@${var.executor_owner_id}/${try(split("/", var.executor_repository)[1], "")}@${var.executor_repository_id}:environment:${role.environment}"
    ], role.subject)])
    error_message = "Each subject must match its executor repository and environment, using the verified legacy or immutable-ID format."
  }
}

variable "state_scope" {
  description = "One authorized backend bucket and team/environment/instance. Keys are derived without wildcard or prefix access."
  type = object({
    bucket_name = string
    team_id     = string
    environment = string
    instance    = string
  })
  nullable = false
  validation {
    condition = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.state_scope.bucket_name)) && alltrue([
      for segment in [var.state_scope.team_id, var.state_scope.environment, var.state_scope.instance] : can(regex("^[A-Za-z0-9][A-Za-z0-9_-]*$", segment))
    ])
    error_message = "Supply an exact bucket name and individual path segments without slashes, traversal or wildcards."
  }
}

variable "backend_access_phases" {
  description = "Explicit opt-in to the existing S3 state/lock permissions by phase. Empty grants no permissions by default."
  type        = set(string)
  default     = []
  nullable    = false
  validation {
    condition     = length(setsubtract(var.backend_access_phases, toset(["plan", "apply", "destroy"]))) == 0
    error_message = "Backend access may only be enabled for plan, apply or destroy."
  }
}
