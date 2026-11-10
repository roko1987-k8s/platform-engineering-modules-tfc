variable "cluster_name" {
  type = string
}
variable "kubernetes_version" {
  type = string
  validation {
    condition     = contains(var.catalog.kubernetes.allowed_versions, var.kubernetes_version)
    error_message = "The node Kubernetes version must match an authorized catalogue version."
  }
}
variable "catalog" {
  type = any
  validation {
    condition     = try(var.catalog.schema_version == 1 && var.catalog.configuration_model == "system_user_profiles" && length(var.catalog.kubernetes.allowed_versions) > 0 && length(var.catalog.cluster.allowed_regions) > 0, false)
    error_message = "A complete authoritative schema_version 1 system_user_profiles catalogue is required."
  }
}
variable "subnet_ids" {
  type = list(string)
}
variable "node_role_arns" {
  type = map(string)
  validation {
    condition     = try(var.node_role_arns.system != var.node_role_arns.user && alltrue([for role in ["system", "user"] : can(regex("^arn:[^:]+:iam::[0-9]{12}:role/.+$", var.node_role_arns[role]))]), false)
    error_message = "System/User require distinct EC2 IAM role ARNs."
  }
}
variable "cluster_security_group_id" {
  description = "EKS cluster security group attached by EKS to the nodes (reported only)."
  type        = string
}
variable "tags" {
  type = map(string)
}
variable "selections" {
  type = map(object({ size = string, capacity_type = string, minimum = number, desired = number, maximum = number, release_version = string, taints = optional(list(object({ key = string, value = optional(string, ""), effect = string })), []) }))
  validation {
    condition     = toset(keys(var.selections)) == toset(["system", "user"])
    error_message = "Exactly System and User must be specified independently."
  }
  validation {
    condition     = alltrue([for role, g in var.selections : try(contains(keys(var.catalog.nodegroups[role].sizes), g.size) && var.catalog.nodegroups[role].sizes[g.size] != null && contains(var.catalog.nodegroups[role].allowed_capacity_types, g.capacity_type) && alltrue([for n in [g.minimum, g.desired, g.maximum] : n >= var.catalog.nodegroups[role].min_count && n <= var.catalog.nodegroups[role].max_count && floor(n) == n]) && var.catalog.nodegroups[role].min_count >= 1 && floor(var.catalog.nodegroups[role].min_count) == var.catalog.nodegroups[role].min_count && floor(var.catalog.nodegroups[role].max_count) == var.catalog.nodegroups[role].max_count && g.minimum <= g.desired && g.desired <= g.maximum && (g.release_version == null || trimspace(coalesce(g.release_version, " ")) != ""), false)])
    error_message = "Profile, capacity, explicit AMI release and ordered integer quantities must satisfy the catalogue per role."
  }
  validation {
    condition     = try(var.catalog.nodegroups.limits.max_total_nodes >= 2 && floor(var.catalog.nodegroups.limits.max_total_nodes) == var.catalog.nodegroups.limits.max_total_nodes && sum([for g in values(var.selections) : g.maximum]) <= var.catalog.nodegroups.limits.max_total_nodes, false)
    error_message = "Sum of maximum node counts exceeds the catalogue aggregate limit."
  }
  validation {
    condition     = alltrue([for g in values(var.selections) : length(distinct([for t in g.taints : "${t.key}:${t.effect}"])) == length(g.taints) && alltrue([for t in g.taints : contains(["NO_SCHEDULE", "NO_EXECUTE", "PREFER_NO_SCHEDULE"], t.effect) && can(regex("^([a-z0-9]([a-z0-9.-]*[a-z0-9])?/)?[A-Za-z0-9]([A-Za-z0-9_.-]{0,61}[A-Za-z0-9])?$", t.key)) && (t.value == "" || can(regex("^[A-Za-z0-9]([A-Za-z0-9_.-]{0,61}[A-Za-z0-9])?$", t.value)))])])
    error_message = "Taints require valid keys/values, supported EKS effects and distinct key/effect pairs."
  }
}

variable "root_volumes" {
  description = "Approved encrypted AL2023 root volume parameters per role; null keeps EBS encryption with the AWS managed key and the AMI root size."
  type        = map(object({ size_gib = number, kms_key_arn = string }))
  default     = null
  validation {
    condition     = var.root_volumes == null ? true : (toset(keys(var.root_volumes)) == toset(["system", "user"]) && alltrue([for v in values(var.root_volumes) : v.size_gib > 0 && floor(v.size_gib) == v.size_gib && can(regex("^arn:[^:]+:kms:[^:]+:[0-9]{12}:key/[A-Za-z0-9-]+$", v.kms_key_arn))]))
    error_message = "Each role needs an explicit positive integer root size and approved customer KMS key ARN; AMI minimum size needs release-specific review."
  }
}
