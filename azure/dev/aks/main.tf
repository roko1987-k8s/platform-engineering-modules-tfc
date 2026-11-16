locals {
  workspace        = "workspaces/${var.team_id}/terraform/azure/${var.environment}/aks-${format("%02d", var.sequence)}"
  team             = var.team_id
  environment      = var.environment
  catalog_path     = "${path.module}/../aks.yaml"
  catalog_document = yamldecode(file(local.catalog_path)).aks
  # schema_version 2 separates node pool profiles per environment; submodules
  # consume the flattened shape for the selected environment.
  catalog = merge(
    { for key, value in local.catalog_document : key => value if key != "environments" },
    { nodepools = local.catalog_document.environments[var.environment].nodepools },
  )
  requested_profiles = { system = var.system_size, user = var.user_size }

  # Modes. DESIGN_WITHOUT_AZURE_SUBSCRIPTION never creates anything. NETWORKING_ONLY
  # creates the VNet, subnets and egress. AKS_CLUSTER adds the cluster on top of the
  # same networking instance, so moving between them never replaces the network.
  execution    = var.proposal_mode != "DESIGN_WITHOUT_AZURE_SUBSCRIPTION"
  cluster_mode = var.proposal_mode == "AKS_CLUSTER"

  networking       = try(var.reviewed_execution.networking, null)
  networking_ready = try(local.execution && var.reviewed_execution != null && local.networking != null && trimspace(local.networking.approval_reference) != "", false)
  admin_groups     = try(var.reviewed_execution.access.admin_group_object_ids, [])
  access_ready     = length(local.admin_groups) > 0
  cluster_ready    = local.cluster_mode && local.networking_ready && local.access_ready

  # Identity tags win over reviewed tags so they cannot be overridden.
  tags = merge(try(var.reviewed_execution.tags, {}), { Team = var.team_id, ApplicationCode = var.application_code, Environment = var.environment })

  selections = {
    for role, size in local.requested_profiles : role => {
      vm_size  = local.catalog.nodepools[role].sizes[size]
      minimum  = var.node_counts[role].minimum
      desired  = var.node_counts[role].desired
      maximum  = var.node_counts[role].maximum
      max_pods = local.catalog.nodepools[role].max_pods
    }
  }

  # Classic Azure CNI reserves max_pods + 1 addresses per node in its subnet. With one
  # surge node during upgrades, the catalog maximum must fit the subnet (Azure keeps 5
  # addresses per subnet). Checked against the catalog maxima, not the request.
  subnet_capacity = {
    for role, cidrs in { system = try(local.networking.system_subnet_cidrs, []), user = try(local.networking.user_subnet_cidrs, []) } :
    role => length(cidrs) == 0 ? 0 : pow(2, 32 - tonumber(split("/", cidrs[0])[1])) - 5
  }
  subnet_demand = {
    for role in ["system", "user"] :
    role => (local.catalog.nodepools[role].max_count + 1) * (local.catalog.nodepools[role].max_pods + 1)
  }
  capacity_ready = alltrue([for role in ["system", "user"] : local.subnet_demand[role] <= local.subnet_capacity[role]])
}

# Blocking preconditions evaluated during plan from variables, locals and pure
# naming only. Modules do not consume this resource's output.
resource "terraform_data" "networking_gate" {
  input = { workspace = local.workspace, mode = var.proposal_mode }
  lifecycle {
    precondition {
      condition     = local.networking_ready
      error_message = "NETWORKING_PENDING: draft files may be reviewed; terraform plan/apply are blocked until the network catalog assigns and approves the VNet and subnet CIDRs."
    }
    precondition {
      condition     = !local.cluster_mode || local.access_ready
      error_message = "ACCESS_PENDING: AKS_CLUSTER requires at least one Platform Engineering Entra ID admin group; local accounts are disabled."
    }
    precondition {
      condition     = !local.cluster_mode || local.capacity_ready
      error_message = "SUBNET_CAPACITY_EXCEEDED: with classic Azure CNI each node reserves max_pods + 1 addresses; the catalog limits (plus one surge node) do not fit the pool subnets."
    }
  }
}

# The credentials Terraform received must belong to the team's reviewed subscription.
data "azurerm_client_config" "current" {
  count = local.networking_ready ? 1 : 0
}
resource "terraform_data" "subscription_gate" {
  count = local.networking_ready ? 1 : 0
  input = var.reviewed_execution.azure_subscription_id
  lifecycle {
    precondition {
      condition     = data.azurerm_client_config.current[0].subscription_id == var.reviewed_execution.azure_subscription_id
      error_message = "SUBSCRIPTION_MISMATCH: the Azure credentials do not belong to the team's reviewed subscription."
    }
  }
}

# The workspace resource group is created by the backend bootstrap, never here.
data "azurerm_resource_group" "workspace" {
  count = local.networking_ready ? 1 : 0
  name  = module.naming.names.rg
}

# Modules use the inherited provider (configured by the team workspace). None has an
# instance in design mode.
module "networking" {
  source              = "./modules/azure/networking"
  count               = local.networking_ready ? 1 : 0
  name                = module.naming.names.vnet
  subnet_names        = module.naming.subnet_names
  location            = var.region
  resource_group_name = data.azurerm_resource_group.workspace[0].name
  networking          = local.networking
  tags                = local.tags
}

module "identity" {
  source              = "./modules/azure/identity"
  count               = local.cluster_ready ? 1 : 0
  name                = module.naming.names.aks
  location            = var.region
  resource_group_name = data.azurerm_resource_group.workspace[0].name
  vnet_id             = module.networking[0].vnet_id
  tags                = local.tags
}

module "aks" {
  source                    = "./modules/azure/aks"
  count                     = local.cluster_ready ? 1 : 0
  name                      = module.naming.names.aks
  location                  = var.region
  resource_group_name       = data.azurerm_resource_group.workspace[0].name
  node_resource_group_name  = "${module.naming.names.rg}-nodes"
  catalog                   = local.catalog.cluster
  kubernetes_version        = var.kubernetes_version
  tenant_id                 = data.azurerm_client_config.current[0].tenant_id
  admin_group_object_ids    = local.admin_groups
  control_plane_identity_id = module.identity[0].control_plane_identity_id
  kubelet                   = module.identity[0].kubelet
  system                    = local.selections.system
  system_subnet_id          = module.networking[0].system_subnet_id
  deletion_protection       = try(var.reviewed_execution.deletion_protection, true)
  tags                      = local.tags
  # Role assignments and NAT associations must exist before the cluster.
  depends_on = [module.identity, module.networking]
}

module "nodepools" {
  source             = "./modules/azure/nodepools"
  count              = local.cluster_ready ? 1 : 0
  cluster_id         = module.aks[0].id
  kubernetes_version = var.kubernetes_version
  user               = local.selections.user
  user_subnet_id     = module.networking[0].user_subnet_id
  tags               = local.tags
}

module "access" {
  source     = "./modules/azure/access"
  count      = local.cluster_ready ? 1 : 0
  cluster_id = module.aks[0].id
  readers    = try(var.reviewed_execution.access.readers, {})
}

# Pure naming is available for review even while networking blocks deployment.
module "naming" {
  source      = "./modules/naming"
  policy      = jsondecode(file("${path.module}/naming/azure.json"))
  region      = var.region
  team_id     = local.team
  environment = local.environment
  sequence    = var.sequence
  subnet_counts = {
    system = length(try(local.networking.system_subnet_cidrs, []))
    user   = length(try(local.networking.user_subnet_cidrs, []))
  }
}
