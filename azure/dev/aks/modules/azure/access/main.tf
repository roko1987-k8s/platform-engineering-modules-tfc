# Read-only access (e.g. the SRE Agent): list kubeconfig plus Kubernetes read
# without Secrets ("Azure Kubernetes Service RBAC Reader" excludes Secrets).
# Admin access is only the Entra ID admin groups set on the cluster.
locals {
  roles = ["Azure Kubernetes Service Cluster User Role", "Azure Kubernetes Service RBAC Reader"]
  assignments = merge([
    for key, principal in var.readers : {
      for role in local.roles : "${key}:${role}" => { principal = principal, role = role }
    }
  ]...)
}

resource "azurerm_role_assignment" "reader" {
  for_each             = local.assignments
  scope                = var.cluster_id
  role_definition_name = each.value.role
  principal_id         = each.value.principal
}
