# User-assigned identities, never a service principal secret. Role assignments are
# scoped to the workspace VNet and to the kubelet identity only (no subscription scope).
resource "azurerm_user_assigned_identity" "control_plane" {
  name                = "${var.name}-control"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "kubelet" {
  name                = "${var.name}-kubelet"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Required by AKS with a custom VNet: manage the load balancer and subnets.
resource "azurerm_role_assignment" "control_plane_network" {
  scope                = var.vnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type       = "ServicePrincipal"
}

# Required by AKS to assign the kubelet identity to the node VMs.
resource "azurerm_role_assignment" "control_plane_kubelet" {
  scope                = azurerm_user_assigned_identity.kubelet.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type       = "ServicePrincipal"
}
