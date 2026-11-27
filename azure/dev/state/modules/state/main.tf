# Terraform state backend of ONE workspace (equivalent of aws/dev/s3): resource group,
# Storage Account and a private blob container. backend "azurerm" locks with a blob
# lease, so no lock resource is needed. Protections are fixed, never parameters.
resource "azurerm_resource_group" "workspace" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_account" "state" {
  name                              = var.storage_account_name
  resource_group_name               = azurerm_resource_group.workspace.name
  location                          = azurerm_resource_group.workspace.location
  account_kind                      = "StorageV2"
  account_tier                      = "Standard"
  account_replication_type          = "LRS"
  access_tier                       = "Hot"
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  local_user_enabled                = false
  sftp_enabled                      = false
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true
  public_network_access_enabled     = true
  tags                              = var.tags

  network_rules {
    # identity: every request still needs an Entra token with a data role on the container.
    default_action = var.network_access == "ip_allowlist" ? "Deny" : "Allow"
    bypass         = ["AzureServices"]
    ip_rules       = var.allowed_ip_ranges
  }

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 30
    }
    container_delete_retention_policy {
      days = 30
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Created through Azure Resource Manager (storage_account_id): no account key and no
# data-plane call through the firewall.
resource "azurerm_storage_container" "state" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
  lifecycle {
    prevent_destroy = true
  }
}

# Azure-side guard: the Storage Account cannot be deleted while the lock exists, even
# outside Terraform. Not on the resource group, which also hosts the cluster.
resource "azurerm_management_lock" "state" {
  name       = "${var.storage_account_name}-no-delete"
  scope      = azurerm_storage_account.state.id
  lock_level = "CanNotDelete"
  notes      = "Terraform state of the workspace."
}

# Entra data roles scoped to the state container only (no account keys). Each assignment
# has a deterministic name (UUIDv5 of the account, container, principal and role), so an
# existing assignment is found by its ID and imported instead of duplicated.
locals {
  state_roles = merge(
    { for id in var.state_access.writers : "writer-${id}" => { principal_id = id, role = "Storage Blob Data Contributor" } },
    { for id in var.state_access.readers : "reader-${id}" => { principal_id = id, role = "Storage Blob Data Reader" } },
  )
}

resource "azurerm_role_assignment" "state" {
  for_each             = local.state_roles
  name                 = uuidv5("url", "adp-state|${var.resource_group_name}|${var.storage_account_name}|tfstate|${each.value.principal_id}|${each.value.role}")
  scope                = azurerm_storage_container.state.id
  role_definition_name = each.value.role
  principal_id         = each.value.principal_id
}
