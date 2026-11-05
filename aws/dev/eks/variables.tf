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
  type    = string
  default = "DESIGN_WITHOUT_AWS_ACCOUNT"
  validation {
    condition     = var.proposal_mode == "DESIGN_WITHOUT_AWS_ACCOUNT"
    error_message = "Only design is supported; this interface does not authorize execution."
  }
}
variable "reviewed_execution" {
  description = "Typed future execution input, not an approval. Design still blocks resource creation when supplied."
  type = object({
    aws_account_id        = string
    resource_prefix       = string
    kms_key_arn           = string
    log_retention_days    = number
    release_versions      = map(string)
    root_volumes          = map(object({ size_gib = number, kms_key_arn = string }))
    tags                  = map(string)
    networking            = object({ conformity = string, vpc_id = string, cluster_subnet_ids = list(string), node_subnet_ids = list(string), connectivity = object({ approval_reference = string, routing_reviewed = bool, private_api_reachable = bool, dns_reviewed = bool, registry_sts_eks_reachable = bool }) })
    security_group_rules  = map(object({ relation = string, source = string, destination = string, protocol = string, from_port = number, to_port = number, approval_reference = string }))
    external_destinations = map(string)
    pod_identity_roles    = map(object({ policy_json = string }))
    addons                = map(object({ version = string, ownership_approved = bool, configuration_values = optional(string), service_account_role_arn = optional(string), pod_identity_associations = optional(map(string), {}) }))
  })
  default = null
}
