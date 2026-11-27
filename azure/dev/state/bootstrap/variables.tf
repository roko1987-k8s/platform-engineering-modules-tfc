variable "subscription_id" {
  description = "Explicitly authorized Azure subscription of the team."
  type        = string
  validation {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "Supply the explicitly authorized Azure subscription ID."
  }
}

variable "network_access" {
  description = "identity (default) or ip_allowlist."
  type        = string
  default     = "identity"
}

variable "allowed_ip_ranges" {
  description = "ip_allowlist only: public IPv4 addresses or ranges allowed through the state firewall."
  type        = list(string)
  default     = []
}
