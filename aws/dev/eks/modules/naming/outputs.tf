output "names" {
  description = "Deterministic proposed names; not reservations, identity evidence or resource creation."
  value       = local.names
  precondition {
    condition     = alltrue([for name in values(local.names) : name == null ? false : length(name) <= 100])
    error_message = "A proposed name is absent or exceeds the existing EKS module's 100-character name limit."
  }
}
