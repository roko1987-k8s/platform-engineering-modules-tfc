output "control_plane_identity_id" {
  value = azurerm_user_assigned_identity.control_plane.id
}
output "kubelet" {
  value = {
    id        = azurerm_user_assigned_identity.kubelet.id
    client_id = azurerm_user_assigned_identity.kubelet.client_id
    object_id = azurerm_user_assigned_identity.kubelet.principal_id
  }
}
# The cluster must wait until both role assignments exist.
output "roles_ready" {
  value = [
    azurerm_role_assignment.control_plane_network.id,
    azurerm_role_assignment.control_plane_kubelet.id,
  ]
}
