locals {
  region_code      = lookup(var.policy.region_codes, var.region, null)
  environment_code = lookup(var.policy.environment_codes, var.environment, null)
  team_code        = lower(var.team_id)
  sequence_text    = try(format("%0${var.policy.sequence_width}d", var.sequence), null)
  # Unknown codes never fall back to a truncated or guessed Azure region string.
  names = {
    for resource, prefix in var.policy.resource_prefixes : resource => (
      local.region_code == null || local.environment_code == null || local.sequence_text == null ? null :
      "${prefix}${local.region_code}${local.team_code}${local.environment_code}${local.sequence_text}"
    )
  }
  # Node pools: <team><role><NN> with role sys, usr or tmp (rotation). AKS Linux pool
  # names allow 1-12 lowercase letters and digits only, so the cluster name does not fit.
  pool_names = {
    for role, code in { system = "sys", user = "usr", rotation = "tmp" } : role => (
      local.sequence_text == null ? null : "${local.team_code}${code}${local.sequence_text}"
    )
  }
  # Subnets derive from the VNet name so they stay grouped with their network.
  subnet_names = {
    for role in ["system", "user", "lb"] : role => (
      local.names.vnet == null ? [] :
      [for i in range(var.subnet_counts[role]) : format("%s-%s-%02d", local.names.vnet, role, i + 1)]
    )
  }
}
