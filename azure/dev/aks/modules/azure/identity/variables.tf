variable "name" {
  description = "names.aks from the naming module."
  type        = string
}
variable "location" {
  type = string
}
variable "resource_group_name" {
  type = string
}
variable "vnet_id" {
  description = "Workspace VNet: the only scope where the control plane gets Network Contributor."
  type        = string
}
variable "tags" {
  type = map(string)
}
