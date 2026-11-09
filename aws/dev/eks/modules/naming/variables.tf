variable "policy" {
  description = "Trusted naming codes, independent from infrastructure allowlists and authorization."
  type        = object({ schema_version = number, region_codes = map(string), environment_codes = map(string), resource_prefixes = map(string), sequence_width = number })
  validation {
    condition     = var.policy.schema_version == 1 && var.policy.sequence_width == 2 && toset(keys(var.policy.resource_prefixes)) == toset(["eks", "vpc", "infra", "user"]) && length(var.policy.region_codes) > 0 && length(var.policy.environment_codes) > 0 && alltrue([for code in concat(values(var.policy.region_codes), values(var.policy.environment_codes), values(var.policy.resource_prefixes)) : can(regex("^[a-z][a-z0-9]*$", code))])
    error_message = "Naming requires schema 1, two-digit minimum sequence width, the four resource prefixes and explicit lowercase alphanumeric codes."
  }
  validation {
    condition     = length(distinct(values(var.policy.region_codes))) == length(var.policy.region_codes) && length(distinct(values(var.policy.environment_codes))) == length(var.policy.environment_codes) && length(distinct(values(var.policy.resource_prefixes))) == length(var.policy.resource_prefixes)
    error_message = "Region, environment and resource naming codes must be unique within each domain."
  }
}
variable "region" {
  type = string
  validation {
    condition     = contains(keys(var.policy.region_codes), var.region)
    error_message = "The AWS region has no approved naming code."
  }
}
variable "environment" {
  type = string
  validation {
    condition     = contains(keys(var.policy.environment_codes), var.environment)
    error_message = "The environment has no approved naming code."
  }
}
variable "team_id" {
  type = string
  validation {
    condition     = can(regex("^[A-Z][0-9]{3}$", var.team_id))
    error_message = "Supply the canonical team code, e.g. D001 or P001. Naming does not authorize this team."
  }
}
variable "sequence" {
  type = number
  validation {
    condition     = var.sequence >= 1 && floor(var.sequence) == var.sequence
    error_message = "Sequence must be a positive integer; leading zero padding is presentation only."
  }
}
variable "subnet_counts" {
  description = "How many public, cluster and node subnet names to derive from names.vpc; zero keeps the previous outputs only."
  type        = object({ public = optional(number, 0), cluster = optional(number, 0), node = optional(number, 0) })
  default     = {}
  validation {
    condition     = alltrue([for n in [var.subnet_counts.public, var.subnet_counts.cluster, var.subnet_counts.node] : n >= 0 && n <= 16 && floor(n) == n])
    error_message = "Subnet counts must be integers between 0 and 16."
  }
}
