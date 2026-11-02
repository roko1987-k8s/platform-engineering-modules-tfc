variable "enabled" {
  type    = bool
  default = false
}
variable "catalog_path" {
  type    = string
  default = "../../../eks.yaml"
}
variable "catalog_commit_sha" {
  type = string
  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.catalog_commit_sha))
    error_message = "Supply the real immutable reviewed catalogue commit SHA."
  }
}
variable "catalog_sha256" {
  type = string
  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.catalog_sha256))
    error_message = "Supply the reviewed catalogue file digest."
  }
}
variable "name" {
  type = string
}
variable "region" {
  type = string
}
variable "kubernetes_version" {
  type = string
}
variable "vpc_id" {
  type = string
}
variable "cluster_subnet_ids" {
  type = list(string)
}
variable "node_subnet_ids" {
  type = list(string)
}
variable "network_option_id" {
  type = string
}
variable "connectivity" {
  type = object({ approval_reference = string, routing_reviewed = bool, private_api_reachable = bool, dns_reviewed = bool, registry_sts_eks_reachable = bool })
}
variable "approvals" {
  type    = object({ generation = bool, provisioning = bool, technical_compatibility = bool, managed_cluster_sg_review = bool, reference = string })
  default = { generation = false, provisioning = false, technical_compatibility = false, managed_cluster_sg_review = false, reference = "" }
}
variable "kms_key_arn" {
  type = string
}
variable "log_retention_days" {
  type = number
}
variable "tags" {
  type = map(string)
}
variable "rules" {
  type    = map(object({ relation = string, source = string, destination = string, protocol = string, from_port = number, to_port = number, approval_reference = string }))
  default = {}
}
variable "external_destinations" {
  type    = map(string)
  default = {}
}
variable "selections" {
  type = map(object({ size = string, capacity_type = string, minimum = number, desired = number, maximum = number, release_version = string, taints = optional(list(object({ key = string, value = optional(string, ""), effect = string })), []) }))
}
variable "addons" {
  type = map(object({ version = string, ownership_approved = bool, configuration_values = optional(string), service_account_role_arn = optional(string), pod_identity_associations = optional(map(string), {}) }))
}
variable "pod_identity_roles" {
  type    = map(object({ policy_json = string }))
  default = {}
}

variable "root_volumes" {
  type = map(object({ size_gib = number, kms_key_arn = string }))
}
