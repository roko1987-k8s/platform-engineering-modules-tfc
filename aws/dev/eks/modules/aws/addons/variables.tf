variable "cluster_name" {
  type = string
}
variable "addons" {
  description = "Explicit versions and ownership approvals only. Empty creates none. vpc-cni needs separately approved workload credentials."
  type        = map(object({ version = string, ownership_approved = bool, configuration_values = optional(string), service_account_role_arn = optional(string), pod_identity_associations = optional(map(string), {}) }))
  default     = {}
  validation {
    condition     = alltrue([for name, a in var.addons : contains(["vpc-cni", "coredns", "kube-proxy", "eks-pod-identity-agent"], name) && can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+-eksbuild\\.[0-9]+$", a.version)) && a.ownership_approved && (a.configuration_values == null || can(jsondecode(a.configuration_values))) && !(a.service_account_role_arn != null && length(a.pod_identity_associations) > 0)])
    error_message = "Select an explicitly approved compatible version, managed ownership and one workload authentication strategy."
  }
  validation {
    condition     = !contains(keys(var.addons), "vpc-cni") || try(var.addons["vpc-cni"].service_account_role_arn != null || contains(keys(var.addons["vpc-cni"].pod_identity_associations), "aws-node"), false)
    error_message = "VPC CNI requires its own approved IRSA role or Pod Identity association; never place its policy on node roles."
  }
  validation {
    condition     = alltrue([for a in values(var.addons) : length(a.pod_identity_associations) == 0 || contains(keys(var.addons), "eks-pod-identity-agent")])
    error_message = "Pod Identity associations require an explicitly managed Pod Identity Agent."
  }
  validation {
    condition     = alltrue([for name, addon in var.addons : name != "eks-pod-identity-agent" || (addon.service_account_role_arn == null && length(addon.pod_identity_associations) == 0)])
    error_message = "The Pod Identity Agent uses the node role; self-referential workload identity is unsupported."
  }
}
variable "tags" {
  type = map(string)
}
