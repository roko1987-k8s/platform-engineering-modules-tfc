variable "enabled" {
  type    = bool
  default = false
}
variable "cluster_name" {
  type = string
}
variable "log_group_name" {
  type = string
}
variable "approval_reference" {
  type    = string
  default = ""
}
variable "metrics" {
  description = "Explicitly selected AWS/EKS Container Insights metric names; an external collector is a separate decision."
  type        = set(string)
  default     = []
  validation {
    condition     = alltrue([for name in var.metrics : can(regex("^[A-Za-z][A-Za-z0-9_]+$", name))])
    error_message = "Metric names must be explicit safe identifiers."
  }
}
