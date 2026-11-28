variable "cluster_id" {
  type = string
}
variable "name" {
  description = "User node pool name from the naming module (<team>usr<NN>)."
  type        = string
}
variable "kubernetes_version" {
  type = string
}
variable "user" {
  description = "Selected user pool: VM size, counts and max pods from the catalog."
  type        = object({ vm_size = string, minimum = number, desired = number, maximum = number, max_pods = number })
}
variable "user_subnet_id" {
  type = string
}
variable "tags" {
  type = map(string)
}
