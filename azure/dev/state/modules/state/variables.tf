variable "resource_group_name" {
  description = "Approved workspace resource group name (names.rg of the instance); the AKS workspace later reads it, never creates it."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^rg[a-z0-9]{1,88}$", var.resource_group_name))
    error_message = "The resource group name is the approved names.rg: rg plus lowercase letters and digits."
  }
}

variable "storage_account_name" {
  description = "Approved state Storage Account name (names.st of the same instance); globally unique in Azure."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^st[a-z0-9]{1,22}$", var.storage_account_name))
    error_message = "The Storage Account name is the approved names.st: st plus lowercase letters and digits, 24 characters at most."
  }
  validation {
    condition     = trimprefix(var.storage_account_name, "st") == trimprefix(var.resource_group_name, "rg")
    error_message = "The Storage Account and the resource group belong to the same instance (same suffix after st/rg)."
  }
}

variable "location" {
  description = "Approved Azure region of the instance."
  type        = string
  nullable    = false
}

variable "tags" {
  description = "Explicit tags supplied by the consuming service or environment."
  type        = map(string)
  nullable    = false
}

variable "network_access" {
  description = "Data plane access model. identity: reachable on the public endpoint, but only Entra identities holding a data role on the container can use it (no keys, no anonymous access). ip_allowlist: additionally, only allowed_ip_ranges reach the account."
  type        = string
  nullable    = false
  default     = "identity"
  validation {
    condition     = contains(["identity", "ip_allowlist"], var.network_access)
    error_message = "network_access is identity or ip_allowlist."
  }
}

variable "allowed_ip_ranges" {
  description = "ip_allowlist only: public IPv4 addresses or ranges (prefix up to /30) allowed through the Storage Account firewall; everything else is denied. Empty with identity."
  type        = list(string)
  nullable    = false
  default     = []
  validation {
    condition = alltrue([
      for range in var.allowed_ip_ranges : can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}(/([0-9]|[12][0-9]|30))?$", range))
    ])
    error_message = "Each entry is a public IPv4 address or a range up to /30 (Azure rejects /31 and /32 in IP rules)."
  }
  validation {
    condition     = (var.network_access == "ip_allowlist") == (length(var.allowed_ip_ranges) > 0)
    error_message = "ip_allowlist needs at least one range; identity takes none."
  }
}

variable "state_access" {
  description = "Entra object IDs granted data access to the state container only: writers (plan/apply, blob lease lock) and readers."
  type = object({
    writers = optional(list(string), [])
    readers = optional(list(string), [])
  })
  nullable = false
  default  = {}
  validation {
    condition = alltrue([
      for id in concat(var.state_access.writers, var.state_access.readers) :
      can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", id))
    ])
    error_message = "State access is granted to Entra object IDs (lowercase GUIDs)."
  }
  validation {
    condition     = length(setintersection(var.state_access.writers, var.state_access.readers)) == 0
    error_message = "A principal is either a writer or a reader of the state, not both."
  }
}
