variable "name" {
  type = string
  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9-]{0,39}$", var.name))
    error_message = "Use a role prefix up to 40 safe characters."
  }
}
variable "tags" {
  type = map(string)
}
variable "pod_identity_roles" {
  description = "Explicit resource-scoped policies for future EKS Pod Identity associations; empty creates no workload roles."
  type        = map(object({ policy_json = string }))
  default     = {}
  validation {
    condition     = alltrue([for p in values(var.pod_identity_roles) : can(jsondecode(p.policy_json).Statement) && try(alltrue([for s in jsondecode(p.policy_json).Statement : s.Effect == "Allow" && length(s.Resource) > 0 && alltrue([for a in flatten([s.Action]) : !strcontains(a, "*")]) && alltrue([for r in flatten([s.Resource]) : r != "*"])]), false)])
    error_message = "Workload policies need explicit actions and resources; no wildcard actions or global resources."
  }
}
variable "node_cni_policy" {
  description = "Attach AmazonEKS_CNI_Policy to node roles for the EKS default (self-managed) vpc-cni."
  type        = bool
  default     = false
}
