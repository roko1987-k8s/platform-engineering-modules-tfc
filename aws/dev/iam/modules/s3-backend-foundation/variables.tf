variable "account_id" {
  description = "Approved AWS account of the S3 backend IAM."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "Supply the exact approved AWS account."
  }
}

variable "region" {
  description = "Approved region of the workspace buckets (must exist in the central naming policy)."
  type        = string
  nullable    = false
}

variable "environment" {
  description = "Approved environment of the workspace buckets (must exist in the central naming policy)."
  type        = string
  nullable    = false
}

variable "agent_principal_arn" {
  description = "The only approved technical source identity: the IAM user adp-agent-dev."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:user/adp-agent-dev$", var.agent_principal_arn))
    error_message = "Trust exactly the IAM user adp-agent-dev; roles, root, STS sessions, federation and wildcards are forbidden."
  }
}

variable "approval" {
  description = "Independent approval evidence of this foundation revision."
  type        = object({ revision = string, reference = string })
  nullable    = false
  validation {
    condition     = can(regex("^[a-f0-9]{64}$", var.approval.revision)) && can(regex("^\\S{1,256}$", var.approval.reference))
    error_message = "Foundation requires an externally approved revision and approval reference."
  }
}
