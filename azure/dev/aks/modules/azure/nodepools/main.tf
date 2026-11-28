resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = var.name
  kubernetes_cluster_id = var.cluster_id
  mode                  = "User"
  vm_size               = var.user.vm_size
  vnet_subnet_id        = var.user_subnet_id
  orchestrator_version  = var.kubernetes_version
  auto_scaling_enabled  = true
  min_count             = var.user.minimum
  max_count             = var.user.maximum
  node_count            = var.user.desired
  max_pods              = var.user.max_pods
  os_disk_type          = "Managed"
  # Same label as the EKS node groups (e.g. the Istio gateway runs on the user nodes).
  node_labels = { "platform.example/node-role" = "user" }
  tags        = var.tags
  upgrade_settings {
    max_surge = "10%"
  }
  lifecycle {
    # The autoscaler owns the current node count after creation.
    ignore_changes = [node_count]
  }
}
