variable "name" {
  type = string
  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,99}$", var.name))
    error_message = "Invalid EKS cluster name."
  }
}
variable "catalog" {
  type = any
  validation {
    condition     = try(var.catalog.schema_version == 1 && var.catalog.configuration_model == "system_user_profiles" && length(var.catalog.kubernetes.allowed_versions) > 0 && length(var.catalog.cluster.allowed_regions) > 0, false)
    error_message = "A complete authoritative schema_version 1 system_user_profiles catalogue is required."
  }
}
variable "kubernetes_version" {
  type = string
  validation {
    condition     = contains(var.catalog.kubernetes.allowed_versions, var.kubernetes_version)
    error_message = "The version must come from the authoritative catalogue."
  }
}
variable "region" {
  type = string
  validation {
    condition     = contains(var.catalog.cluster.allowed_regions, var.region)
    error_message = "The region must come from the authoritative catalogue."
  }
}
variable "role_arn" {
  type = string
}
variable "subnet_ids" {
  type = list(string)
  validation {
    condition     = length(distinct(var.subnet_ids)) >= 2
    error_message = "At least two validated subnets are required."
  }
}
variable "kms_key_arn" {
  description = "Approved customer KMS key ARN; null uses EKS default secrets encryption."
  type        = string
  default     = null
  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:[^:]+:kms:[^:]+:[0-9]{12}:key/[A-Za-z0-9-]+$", var.kms_key_arn))
    error_message = "Supply an approved customer KMS key ARN, not an alias."
  }
}
variable "log_retention_days" {
  description = "Control-plane log retention; null disables control-plane logging and its log group."
  type        = number
  default     = null
  validation {
    condition     = var.log_retention_days == null ? true : contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "Choose a supported finite CloudWatch retention period."
  }
}
variable "bootstrap_self_managed_addons" {
  description = "Let EKS install its default vpc-cni, kube-proxy and CoreDNS (only when no managed add-ons are approved)."
  type        = bool
  default     = false
}
variable "deletion_protection" {
  description = "EKS deletion protection; a lab create/destroy cycle may set it to false explicitly."
  type        = bool
  default     = true
}
variable "tags" {
  type = map(string)
}
