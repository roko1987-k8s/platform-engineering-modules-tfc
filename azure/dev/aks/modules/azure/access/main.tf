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

# --- Private API without a jump host: az aks command invoke ---------------------------
# Runs kubectl/helm inside the cluster through the Azure API (no network path to the
# private endpoint). Narrow custom role of this cluster: read it, run a command and read
# the result; Kubernetes authorization stays with the caller's own Azure RBAC role below.
resource "azurerm_role_definition" "command_invoke" {
  name              = "${var.name}-command-invoke"
  scope             = var.resource_group_id
  description       = "az aks command invoke on ${var.name} only (no credentials, no cluster changes)."
  assignable_scopes = [var.resource_group_id]
  permissions {
    actions = [
      "Microsoft.ContainerService/managedClusters/read",
      "Microsoft.ContainerService/managedClusters/runcommand/action",
      "Microsoft.ContainerService/managedClusters/commandResults/read",
    ]
  }
}

# --- Destroy pre-step: stop Argo CD and delete LoadBalancer Services/Ingresses ----------
# The same Kubernetes calls as group adp:destroy-cleanup on EKS, as Azure RBAC data actions
# (no Kubernetes RBAC objects needed, nothing else readable or writable).
resource "azurerm_role_definition" "cleanup" {
  name              = "${var.name}-destroy-cleanup"
  scope             = var.resource_group_id
  description       = "Destroy pre-step on ${var.name}: scale Argo CD's controller, delete LoadBalancer Services and Ingresses."
  assignable_scopes = [var.resource_group_id]
  permissions {
    data_actions = [
      "Microsoft.ContainerService/managedClusters/apps/statefulsets/read",
      "Microsoft.ContainerService/managedClusters/apps/statefulsets/write",
      "Microsoft.ContainerService/managedClusters/services/read",
      "Microsoft.ContainerService/managedClusters/services/delete",
      "Microsoft.ContainerService/managedClusters/networking.k8s.io/ingresses/read",
      "Microsoft.ContainerService/managedClusters/networking.k8s.io/ingresses/delete",
    ]
  }
}

locals {
  # Agent identities of THIS cluster's team (one principal per team and purpose, issued by
  # the platform): Azure has no session tags, so team isolation is the principal itself.
  #   bot      read-only view (no Secrets)           ~ EKS AmazonEKSViewPolicy
  #   tools    cluster admin, Argo CD bootstrap only  ~ EKS AmazonEKSClusterAdminPolicy
  #   cleanup  the Destroy's pre-step                 ~ EKS group adp:destroy-cleanup
  agent_roles = {
    bot     = "Azure Kubernetes Service RBAC Reader"
    tools   = "Azure Kubernetes Service RBAC Cluster Admin"
    cleanup = null # custom role above
  }
  agents = { for purpose, id in var.agents : purpose => id if id != null }
  invokers = merge(
    { for id in var.admin_group_object_ids : "admin:${id}" => { principal = id, type = "Group" } },
    { for purpose, id in local.agents : "agent:${purpose}" => { principal = id, type = "ServicePrincipal" } },
  )
}

resource "azurerm_role_assignment" "command_invoke" {
  for_each           = local.invokers
  scope              = var.cluster_id
  role_definition_id = azurerm_role_definition.command_invoke.role_definition_resource_id
  principal_id       = each.value.principal
  principal_type     = each.value.type
}

resource "azurerm_role_assignment" "agent" {
  for_each             = { for purpose, id in local.agents : purpose => id if local.agent_roles[purpose] != null }
  scope                = var.cluster_id
  role_definition_name = local.agent_roles[each.key]
  principal_id         = each.value
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "cleanup" {
  for_each           = { for purpose, id in local.agents : purpose => id if purpose == "cleanup" }
  scope              = var.cluster_id
  role_definition_id = azurerm_role_definition.cleanup.role_definition_resource_id
  principal_id       = each.value
  principal_type     = "ServicePrincipal"
}
