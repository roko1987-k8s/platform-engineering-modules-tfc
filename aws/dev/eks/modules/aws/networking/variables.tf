variable "vpc_id" {
  type = string
  validation {
    condition     = can(regex("^vpc-([0-9a-f]{8}|[0-9a-f]{17})$", var.vpc_id))
    error_message = "An approved VPC ID is required."
  }
}
variable "cluster_subnet_ids" {
  type = list(string)
  validation {
    condition     = length(var.cluster_subnet_ids) >= 2 && length(distinct(var.cluster_subnet_ids)) == length(var.cluster_subnet_ids) && alltrue([for id in var.cluster_subnet_ids : can(regex("^subnet-([0-9a-f]{8}|[0-9a-f]{17})$", id))])
    error_message = "Provide at least two distinct approved cluster subnet IDs."
  }
}
variable "node_subnet_ids" {
  type = list(string)
  validation {
    condition     = length(var.node_subnet_ids) >= 2 && length(distinct(var.node_subnet_ids)) == length(var.node_subnet_ids) && alltrue([for id in var.node_subnet_ids : can(regex("^subnet-([0-9a-f]{8}|[0-9a-f]{17})$", id))])
    error_message = "Provide at least two distinct approved private node subnet IDs."
  }
}
variable "conformity" {
  type = string
  validation {
    condition     = var.conformity == "approved"
    error_message = "Networking conformity must be explicitly approved."
  }
}
variable "connectivity" {
  type = object({ approval_reference = string, routing_reviewed = bool, private_api_reachable = bool, dns_reviewed = bool, registry_sts_eks_reachable = bool })
  validation {
    condition     = trimspace(var.connectivity.approval_reference) != "" && var.connectivity.routing_reviewed && var.connectivity.private_api_reachable && var.connectivity.dns_reviewed && var.connectivity.registry_sts_eks_reachable
    error_message = "Networking must supply a reviewed routing, DNS, private API, ECR/S3/STS/EKS connectivity contract."
  }
}
