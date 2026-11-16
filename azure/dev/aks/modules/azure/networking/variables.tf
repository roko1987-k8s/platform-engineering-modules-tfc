variable "name" {
  description = "names.vnet from the naming module."
  type        = string
}
variable "subnet_names" {
  description = "Subnet names per role from the naming module, in CIDR order."
  type        = object({ system = list(string), user = list(string) })
}
variable "location" {
  type = string
}
variable "resource_group_name" {
  description = "Existing workspace resource group (created by the backend bootstrap, never here)."
  type        = string
}
variable "networking" {
  description = "Approved networking: one VNet block and one subnet per node pool role."
  type = object({
    vnet_cidr           = string
    system_subnet_cidrs = list(string)
    user_subnet_cidrs   = list(string)
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
}
variable "tags" {
  type = map(string)
}
