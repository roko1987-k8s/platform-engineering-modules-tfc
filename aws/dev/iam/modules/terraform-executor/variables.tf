variable "vault_principal_arn" {
  description = "Exact IAM principal used by the Vault AWS secrets engine to call sts:AssumeRole. The only trusted principal."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^arn:aws(-[a-z-]+)?:iam::[0-9]{12}:(role|user)/[A-Za-z0-9+=,.@_/-]{1,128}$", var.vault_principal_arn))
    error_message = "Supply the exact Vault IAM principal ARN, without wildcards."
  }
}

variable "roles" {
  description = "Exactly plan/apply/destroy with approved, distinct role names. Shared by all teams: per-team scope comes from the Vault session policy."
  type        = map(object({ name = string }))
  nullable    = false
  validation {
    condition     = toset(keys(var.roles)) == toset(["plan", "apply", "destroy"])
    error_message = "Define exactly plan, apply and destroy."
  }
  validation {
    condition     = alltrue([for r in values(var.roles) : can(regex("^[A-Za-z0-9_+=,.@-]{1,64}$", r.name))]) && length(distinct([for r in values(var.roles) : lower(r.name)])) == 3
    error_message = "Use three distinct, exact IAM role names."
  }
}

variable "state_buckets" {
  description = "Approved per-team backend buckets from the Terraform Agent backend registry."
  type        = set(string)
  nullable    = false
  validation {
    condition     = length(var.state_buckets) > 0 && alltrue([for b in var.state_buckets : can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", b))])
    error_message = "Supply at least one exact bucket name."
  }
}

variable "region" {
  description = "Catalog region (aws/dev/eks.yaml); provisioning is denied in any other region."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "Supply the catalog region."
  }
}

variable "provisioning_phases" {
  description = "Explicit opt-in to the reviewed networking provisioning policies by phase. Empty attaches none (provisioning blocked)."
  type        = set(string)
  default     = []
  nullable    = false
  validation {
    condition     = length(setsubtract(var.provisioning_phases, toset(["plan", "apply", "destroy"]))) == 0
    error_message = "Provisioning may only be enabled for plan, apply or destroy."
  }
}

variable "tags" {
  type    = map(string)
  default = {}
}
