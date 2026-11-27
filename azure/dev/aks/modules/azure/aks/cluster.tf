# Ordering (role assignments, NAT associations) comes from depends_on in the root
# composition, never from data coupling that could force a cluster replacement.
resource "azurerm_kubernetes_cluster" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  node_resource_group = var.node_resource_group_name
  dns_prefix          = var.name
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.catalog.sku_tier

  # Private API only (equivalent to the EKS private endpoint, TD-049 option B).
  private_cluster_enabled             = true
  private_cluster_public_fqdn_enabled = false

  # No local admin kubeconfig: every access goes through Entra ID and Azure RBAC.
  local_account_disabled            = true
  role_based_access_control_enabled = true
  azure_active_directory_role_based_access_control {
    tenant_id              = var.tenant_id
    azure_rbac_enabled     = true
    admin_group_object_ids = var.admin_group_object_ids
  }

  # az aks command invoke is the only path to the private API (no jump host in the VNet).
  run_command_enabled = true

  # Workload identity for in-cluster agents (no static credentials).
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  identity {
    type         = "UserAssigned"
    identity_ids = [var.control_plane_identity_id]
  }
  kubelet_identity {
    user_assigned_identity_id = var.kubelet.id
    client_id                 = var.kubelet.client_id
    object_id                 = var.kubelet.object_id
  }

  default_node_pool {
    name                         = "system"
    vm_size                      = var.system.vm_size
    vnet_subnet_id               = var.system_subnet_id
    orchestrator_version         = var.kubernetes_version
    only_critical_addons_enabled = true
    auto_scaling_enabled         = true
    min_count                    = var.system.minimum
    max_count                    = var.system.maximum
    node_count                   = var.system.desired
    max_pods                     = var.system.max_pods
    os_disk_type                 = "Managed"
    temporary_name_for_rotation  = "systemtmp"
    tags                         = var.tags
    upgrade_settings {
      max_surge = "10%"
    }
  }

  # Classic Azure CNI (no network_plugin_mode): pods take addresses of their pool subnet.
  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    load_balancer_sku = "standard"
    outbound_type     = "userAssignedNATGateway"
    service_cidr      = var.catalog.service_cidr
    dns_service_ip    = var.catalog.dns_service_ip
  }

  tags = var.tags

  lifecycle {
    # The autoscaler owns the current node count after creation.
    ignore_changes = [default_node_pool[0].node_count]
    precondition {
      condition     = var.catalog.private_cluster == true
      error_message = "The central catalog must keep the AKS cluster private."
    }
  }
}

resource "azurerm_management_lock" "cluster" {
  count      = var.deletion_protection ? 1 : 0
  name       = "${var.name}-cannot-delete"
  scope      = azurerm_kubernetes_cluster.this.id
  lock_level = "CanNotDelete"
  notes      = "Remove only through a reviewed change."
}
