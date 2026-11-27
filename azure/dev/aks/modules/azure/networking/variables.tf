variable "name" {
  description = "names.vnet from the naming module."
  type        = string
}
variable "subnet_names" {
  description = "Subnet names per role from the naming module, in CIDR order."
  type        = object({ system = list(string), user = list(string), lb = optional(list(string), []) })
}
variable "location" {
  type = string
}
variable "resource_group_name" {
  description = "Existing workspace resource group (created by the backend bootstrap, never here)."
  type        = string
}
variable "networking" {
  description = "Approved networking: one VNet block, one subnet per node pool role and, optionally, the internal load balancer subnet."
  type = object({
    vnet_cidr           = string
    system_subnet_cidrs = list(string)
    user_subnet_cidrs   = list(string)
    lb_subnet_cidrs     = optional(list(string), [])
    approval_reference  = string
  })
  validation {
    # Containment in the VNet is guaranteed by the deterministic catalog derivation
    # (Regla A) and re-checked by the Terraform Agent; Terraform has no native CIDR containment.
    condition     = can(cidrhost(var.networking.vnet_cidr, 0)) && length(var.networking.system_subnet_cidrs) == 1 && length(var.networking.user_subnet_cidrs) == 1 && alltrue([for cidr in concat(var.networking.system_subnet_cidrs, var.networking.user_subnet_cidrs) : can(cidrhost(cidr, 0))])
    error_message = "Networking requires a valid VNet CIDR and exactly one valid system and one valid user subnet CIDR."
  }
  validation {
    condition     = trimspace(var.networking.approval_reference) != ""
    error_message = "An approval reference from the network catalog is required."
  }
  validation {
    condition     = length(var.networking.lb_subnet_cidrs) <= 1 && alltrue([for cidr in var.networking.lb_subnet_cidrs : can(cidrhost(cidr, 4))])
    error_message = "At most one valid internal load balancer subnet CIDR is allowed."
  }
}
variable "rules_catalog" {
  description = "network/rules.yaml (adp-network-rules-v1): the rules of every cluster, defined once for all clouds."
  type        = any
}
variable "tags" {
  type = map(string)
}
