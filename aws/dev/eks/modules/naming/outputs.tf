output "names" {
  description = "Deterministic proposed names; not reservations, identity evidence or resource creation."
  value       = local.names
  precondition {
    condition     = alltrue([for name in values(local.names) : name == null ? false : length(name) <= 100])
    error_message = "A proposed name is absent or exceeds the existing EKS module's 100-character name limit."
  }
}
output "subnet_names" {
  description = "Deterministic subnet names <names.vpc>-<role>-NN, in CIDR order; empty unless subnet_counts is set."
  value       = local.subnet_names
  precondition {
    condition     = alltrue([for name in flatten(values(local.subnet_names)) : length(name) <= 100])
    error_message = "A proposed subnet name exceeds the 100-character limit."
  }
}
