variable "team_id" {
  type = string
  validation {
    condition     = can(regex("^[DP][0-9]{3}$", var.team_id))
    error_message = "A backend-authorized canonical team is required; naming does not grant access."
  }
}
variable "application_code" {
  type = string
  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,39}$", var.application_code))
    error_message = "Application must come from the authorized backend binding."
  }
}
variable "environment" {
  type = string
  validation {
    condition     = var.environment == "dev"
    error_message = "This composition belongs to aws/dev."
  }
}
variable "region" {
  type = string
  validation {
    condition     = contains(local.catalog.cluster.allowed_regions, var.region)
    error_message = "Region is not authorized by the central catalog."
  }
}
variable "sequence" {
  type = number
  validation {
    condition     = var.sequence >= 1 && var.sequence <= 99 && floor(var.sequence) == var.sequence
    error_message = "An authorized integer sequence between 1 and 99 is required."
  }
}
variable "kubernetes_version" {
  type = string
  validation {
    condition     = contains(local.catalog.kubernetes.allowed_versions, var.kubernetes_version)
    error_message = "Kubernetes version is not authorized by the central catalog."
  }
}
variable "system_size" {
  type = string
  validation {
    condition     = contains(keys(local.catalog.nodegroups.system.sizes), var.system_size)
    error_message = "System size must be present in the central catalog."
  }
}
variable "user_size" {
  type = string
  validation {
    condition     = contains(keys(local.catalog.nodegroups.user.sizes), var.user_size)
    error_message = "User size must be present in the central catalog."
  }
}
variable "node_counts" {
  type = object({ system = object({ minimum = number, desired = number, maximum = number }), user = object({ minimum = number, desired = number, maximum = number }) })
  validation {
    condition     = alltrue([for role, counts in var.node_counts : counts.minimum <= counts.desired && counts.desired <= counts.maximum && alltrue([for n in [counts.minimum, counts.desired, counts.maximum] : floor(n) == n && n >= local.catalog.nodegroups[role].min_count && n <= local.catalog.nodegroups[role].max_count])]) && sum([for counts in values(var.node_counts) : counts.maximum]) <= local.catalog.nodegroups.limits.max_total_nodes
    error_message = "Counts must be ordered integers within per-role and aggregate catalog limits."
  }
}
variable "proposal_mode" {
  description = "DESIGN_WITHOUT_AWS_ACCOUNT (default, blocked), NETWORKING_ONLY (VPC/subnets/egress only) or EKS_CLUSTER (networking plus cluster). Execution still requires the Terraform Agent's independent authorization."
  type        = string
  default     = "DESIGN_WITHOUT_AWS_ACCOUNT"
  validation {
    condition     = contains(["DESIGN_WITHOUT_AWS_ACCOUNT", "NETWORKING_ONLY", "EKS_CLUSTER"], var.proposal_mode)
    error_message = "proposal_mode must be DESIGN_WITHOUT_AWS_ACCOUNT, NETWORKING_ONLY or EKS_CLUSTER."
  }
}
variable "reviewed_execution" {
  description = "Reviewed execution inputs, not an approval. NETWORKING_ONLY needs only aws_account_id and networking; EKS_CLUSTER also needs resource_prefix, kms_key_arn, log_retention_days and root_volumes."
  type = object({
    aws_account_id = string
    # Single Networking object; validated by modules/aws/networking.
    networking = optional(object({
      vpc_cidr             = string
      public_subnet_cidrs  = list(string)
      cluster_subnet_cidrs = list(string)
      node_subnet_cidrs    = list(string)
      approval_reference   = string
      connectivity         = optional(object({ routing_reviewed = bool, private_api_reachable = bool, dns_reviewed = bool, registry_sts_eks_reachable = bool }))
    }))
    resource_prefix       = optional(string)
    kms_key_arn           = optional(string)
    log_retention_days    = optional(number)
    release_versions      = optional(map(string), {})
    root_volumes          = optional(map(object({ size_gib = number, kms_key_arn = string })))
    tags                  = optional(map(string), {})
    security_group_rules  = optional(map(object({ relation = string, source = string, destination = string, protocol = string, from_port = number, to_port = number, approval_reference = string })), {})
    external_destinations = optional(map(string), {})
    pod_identity_roles    = optional(map(object({ policy_json = string })), {})
    addons                = optional(map(object({ version = string, ownership_approved = bool, configuration_values = optional(string), service_account_role_arn = optional(string), pod_identity_associations = optional(map(string), {}) })), {})
  })
  default = null
  validation {
    condition     = var.reviewed_execution == null || can(regex("^[0-9]{12}$", var.reviewed_execution.aws_account_id))
    error_message = "aws_account_id must be the 12-digit approved target account."
  }
}
