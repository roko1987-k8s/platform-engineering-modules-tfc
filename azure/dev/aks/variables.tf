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
    error_message = "This composition belongs to azure/dev."
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
    condition     = contains(keys(local.catalog.nodepools.system.sizes), var.system_size)
    error_message = "System size must be present in the central catalog."
  }
}
variable "user_size" {
  type = string
  validation {
    condition     = contains(keys(local.catalog.nodepools.user.sizes), var.user_size)
    error_message = "User size must be present in the central catalog."
  }
}
variable "node_counts" {
  type = object({ system = object({ minimum = number, desired = number, maximum = number }), user = object({ minimum = number, desired = number, maximum = number }) })
  validation {
    condition     = alltrue([for role, counts in var.node_counts : counts.minimum <= counts.desired && counts.desired <= counts.maximum && alltrue([for n in [counts.minimum, counts.desired, counts.maximum] : floor(n) == n && n >= local.catalog.nodepools[role].min_count && n <= local.catalog.nodepools[role].max_count])]) && sum([for counts in values(var.node_counts) : counts.maximum]) <= local.catalog.nodepools.limits.max_total_nodes
    error_message = "Counts must be ordered integers within per-role and aggregate catalog limits."
  }
}
variable "proposal_mode" {
  description = "DESIGN_WITHOUT_AZURE_SUBSCRIPTION (default, blocked), NETWORKING_ONLY (VNet/subnets/egress only) or AKS_CLUSTER (networking plus cluster). Execution still requires the Terraform Agent's independent authorization."
  type        = string
  default     = "DESIGN_WITHOUT_AZURE_SUBSCRIPTION"
  validation {
    condition     = contains(["DESIGN_WITHOUT_AZURE_SUBSCRIPTION", "NETWORKING_ONLY", "AKS_CLUSTER"], var.proposal_mode)
    error_message = "proposal_mode must be DESIGN_WITHOUT_AZURE_SUBSCRIPTION, NETWORKING_ONLY or AKS_CLUSTER."
  }
}
variable "reviewed_execution" {
  description = "Reviewed execution inputs, not an approval. One subscription per team (injected by the Terraform Agent, never stored in Git). Names come from module.naming."
  type = object({
    azure_subscription_id = string
    # Deterministic networking from the Azure network catalog (Regla A).
    networking = optional(object({
      vnet_cidr           = string
      system_subnet_cidrs = list(string)
      user_subnet_cidrs   = list(string)
      approval_reference  = string
    }))
    # Platform Engineering admin groups and read-only principals by purpose (e.g. sre_agent).
    access = optional(object({
      admin_group_object_ids = list(string)
      readers                = optional(map(string), {})
    }), { admin_group_object_ids = [] })
    tags                = optional(map(string), {})
    deletion_protection = optional(bool, true)
  })
  default = null
  validation {
    condition     = var.reviewed_execution == null || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.reviewed_execution.azure_subscription_id))
    error_message = "azure_subscription_id must be the approved subscription GUID of the team."
  }
}
