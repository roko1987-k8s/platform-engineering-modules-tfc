locals {
  workspace          = "workspaces/${var.team_id}/terraform/aws/${var.environment}/eks-${format("%02d", var.sequence)}"
  team               = var.team_id
  environment        = var.environment
  deployment         = "eks-${format("%02d", var.sequence)}"
  catalog_path       = "${path.module}/../eks.yaml"
  catalog            = yamldecode(file(local.catalog_path)).eks
  requested_profiles = { system = var.system_size, user = var.user_size }

  requested_counts = var.node_counts

  # Networking owns completion and approval. No CIDR or invented segment exists.
  # Design-only contract: execution is not implemented or authorized by this module.
  design_only      = var.proposal_mode == "DESIGN_WITHOUT_AWS_ACCOUNT"
  networking       = try(var.reviewed_execution.networking, null)
  networking_ready = try(!local.design_only && var.reviewed_execution != null && local.networking.conformity == "approved" && local.networking.vpc_id != null && length(local.networking.cluster_subnet_ids) >= 2 && length(local.networking.node_subnet_ids) >= 2 && local.networking.connectivity != null, false)

  selections = {
    for role, size in local.requested_profiles : role => {
      size = size
      # Select only when the authoritative catalogue has exactly one choice.
      capacity_type   = one(local.catalog.nodegroups[role].allowed_capacity_types)
      minimum         = local.requested_counts[role].minimum
      desired         = local.requested_counts[role].desired
      maximum         = local.requested_counts[role].maximum
      release_version = try(var.reviewed_execution.release_versions[role], null)
    }
  }
}

# A lifecycle precondition is a blocking error, unlike an advisory check block.
# It runs even though deployment modules have zero instances in the draft.
resource "terraform_data" "networking_gate" {
  input = { workspace = local.workspace, networking = local.networking, execution = var.reviewed_execution }
  lifecycle {
    precondition {
      condition     = local.networking_ready
      error_message = "NETWORKING_PENDING: draft files may be reviewed; terraform plan/apply are blocked until Networking supplies and approves real segments."
    }
  }
}

# Modules use an inherited provider. None has an instance in this draft.

module "networking" {
  source             = "./modules/aws/networking"
  count              = local.networking_ready ? 1 : 0
  vpc_id             = terraform_data.networking_gate.output.networking.vpc_id
  cluster_subnet_ids = terraform_data.networking_gate.output.networking.cluster_subnet_ids
  node_subnet_ids    = terraform_data.networking_gate.output.networking.node_subnet_ids
  conformity         = terraform_data.networking_gate.output.networking.conformity
  connectivity       = terraform_data.networking_gate.output.networking.connectivity
  depends_on         = [terraform_data.networking_gate]
}
module "iam" {
  source             = "./modules/aws/iam"
  count              = local.networking_ready ? 1 : 0
  name               = try(terraform_data.networking_gate.output.execution.resource_prefix, null)
  pod_identity_roles = try(var.reviewed_execution.pod_identity_roles, {})
  tags               = try(var.reviewed_execution.tags, {})
  depends_on         = [terraform_data.networking_gate, module.networking]
}
module "security_groups" {
  source                = "./modules/aws/security-groups"
  count                 = local.networking_ready ? 1 : 0
  name                  = try(terraform_data.networking_gate.output.execution.resource_prefix, null)
  vpc_id                = module.networking[0].vpc_id
  tags                  = try(var.reviewed_execution.tags, {})
  rules                 = try(var.reviewed_execution.security_group_rules, {})
  external_destinations = try(var.reviewed_execution.external_destinations, {})
  depends_on            = [terraform_data.networking_gate]
}
module "eks" {
  source                          = "./modules/aws/eks"
  count                           = local.networking_ready ? 1 : 0
  name                            = module.naming.names.eks
  catalog                         = local.catalog
  kubernetes_version              = var.kubernetes_version
  region                          = var.region
  role_arn                        = module.iam[0].cluster_role_arn
  subnet_ids                      = module.networking[0].cluster_subnet_ids
  control_plane_security_group_id = module.security_groups[0].security_group_ids.control_plane
  kms_key_arn                     = try(terraform_data.networking_gate.output.execution.kms_key_arn, null)
  log_retention_days              = try(terraform_data.networking_gate.output.execution.log_retention_days, null)
  tags                            = try(var.reviewed_execution.tags, {})
  depends_on                      = [terraform_data.networking_gate]
}
module "foundation_addons" {
  source       = "./modules/aws/addons"
  count        = local.networking_ready ? 1 : 0
  cluster_name = module.eks[0].name
  addons       = try({ for name, addon in var.reviewed_execution.addons : name => addon if name != "coredns" }, {})
  tags         = try(var.reviewed_execution.tags, {})
  depends_on   = [terraform_data.networking_gate]
}
module "nodegroups" {
  source             = "./modules/aws/nodegroups"
  count              = local.networking_ready ? 1 : 0
  cluster_name       = module.eks[0].name
  kubernetes_version = var.kubernetes_version
  catalog            = local.catalog
  subnet_ids         = module.networking[0].node_subnet_ids
  node_role_arns     = module.iam[0].node_role_arns
  security_group_ids = module.security_groups[0].security_group_ids
  selections         = local.selections
  root_volumes       = try(terraform_data.networking_gate.output.execution.root_volumes, null)
  tags               = try(var.reviewed_execution.tags, {})
  depends_on         = [terraform_data.networking_gate, module.foundation_addons]
}
module "dns_addon" {
  source       = "./modules/aws/addons"
  count        = local.networking_ready ? 1 : 0
  cluster_name = module.eks[0].name
  addons       = try({ for name, addon in var.reviewed_execution.addons : name => addon if name == "coredns" }, {})
  tags         = try(var.reviewed_execution.tags, {})
  depends_on   = [terraform_data.networking_gate, module.nodegroups]
}

# Pure naming is available for review even while networking blocks deployment.
module "naming" {
  source      = "./modules/naming"
  policy      = jsondecode(file("${path.module}/naming/aws.json"))
  region      = var.region
  team_id     = local.team
  environment = local.environment
  sequence    = var.sequence
}
