locals {
  region_code      = lookup(var.policy.region_codes, var.region, null)
  environment_code = lookup(var.policy.environment_codes, var.environment, null)
  team_code        = lower(var.team_id)
  sequence_text    = try(format("%0${var.policy.sequence_width}d", var.sequence), null)
  # Unknown codes never fall back to a truncated or guessed AWS region string.
  names = {
    for resource, prefix in var.policy.resource_prefixes : resource => (
      local.region_code == null || local.environment_code == null || local.sequence_text == null ? null :
      "${prefix}${local.region_code}${local.team_code}${local.environment_code}${local.sequence_text}"
    )
  }
  # Subnets derive from the VPC name so they stay grouped with their network.
  subnet_names = {
    for role in ["public", "cluster", "node"] : role => (
      local.names.vpc == null ? [] :
      [for i in range(var.subnet_counts[role]) : format("%s-%s-%02d", local.names.vpc, role, i + 1)]
    )
  }
}
