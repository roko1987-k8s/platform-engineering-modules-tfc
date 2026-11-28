output "names" {
  description = "Deterministic proposed names; not reservations, identity evidence or resource creation."
  value       = local.names
  precondition {
    condition     = alltrue([for name in values(local.names) : name == null ? false : length(name) <= 63])
    error_message = "A proposed name is absent or exceeds 63 characters."
  }
  # Storage accounts: 3-24 lowercase letters and digits, globally unique (uniqueness is checked by Azure, not here).
  precondition {
    condition     = can(regex("^[a-z0-9]{3,24}$", local.names.st))
    error_message = "The proposed storage account name is not a valid Azure storage account name."
  }
  # AKS dns_prefix: starts with a letter, letters, digits and hyphens, at most 54 characters.
  precondition {
    condition     = can(regex("^[a-z][a-z0-9-]{0,53}$", local.names.aks))
    error_message = "The proposed AKS name is not a valid AKS DNS prefix."
  }
}
output "pool_names" {
  description = "Deterministic AKS node pool names <team><role><NN> for system, user and the system pool rotation."
  value       = local.pool_names
  precondition {
    condition     = alltrue([for name in values(local.pool_names) : can(regex("^[a-z][a-z0-9]{0,11}$", name))])
    error_message = "A proposed node pool name is not a valid AKS Linux pool name (1-12 lowercase letters and digits)."
  }
}
output "subnet_names" {
  description = "Deterministic subnet names <names.vnet>-<role>-NN, in CIDR order; empty unless subnet_counts is set."
  value       = local.subnet_names
}
