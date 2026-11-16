variable "name" {
  description = "names.aks from the naming module; also the DNS prefix."
  type        = string
}
variable "location" {
  type = string
}
variable "resource_group_name" {
  type = string
}
variable "node_resource_group_name" {
  description = "Resource group AKS creates for the node infrastructure; must not exist beforehand."
  type        = string
}
variable "catalog" {
  description = "Selected central catalog (cluster block)."
  type        = any
}
variable "kubernetes_version" {
  type = string
}
variable "tenant_id" {
  description = "Entra ID tenant of the verified subscription."
  type        = string
}
variable "admin_group_object_ids" {
  description = "Entra ID groups with cluster admin (Platform Engineering only). Local accounts are disabled."
  type        = list(string)
  validation {
    condition     = length(var.admin_group_object_ids) > 0 && alltrue([for id in var.admin_group_object_ids : can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", id))])
    error_message = "At least one Entra ID admin group object ID (GUID) is required."
  }
}
variable "control_plane_identity_id" {
  type = string
}
variable "kubelet" {
  type = object({ id = string, client_id = string, object_id = string })
}
variable "system" {
  description = "Selected system pool: VM size, counts and max pods from the catalog."
  type        = object({ vm_size = string, minimum = number, desired = number, maximum = number, max_pods = number })
}
variable "system_subnet_id" {
  type = string
}
variable "deletion_protection" {
  description = "Adds a CanNotDelete management lock on the cluster (lab create/destroy cycles set false)."
  type        = bool
  default     = true
}
variable "tags" {
  type = map(string)
}
