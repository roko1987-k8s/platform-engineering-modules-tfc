locals {
  workspace        = "workspaces/${var.team_id}/terraform/aws/${var.environment}/eks-${format("%02d", var.sequence)}"
  team             = var.team_id
  environment      = var.environment
  deployment       = "eks-${format("%02d", var.sequence)}"
  catalog_path     = "${path.module}/../eks.yaml"
  catalog_document = yamldecode(file(local.catalog_path)).eks
  # schema_version 2 separates profiles per environment. Submodules, variable
  # validations and outputs keep consuming the v1 shape for the selected one.
  catalog = merge(
    { for key, value in local.catalog_document : key => value if key != "environments" },
    {
      schema_version = 1
      nodegroups     = local.catalog_document.environments[var.environment].nodegroups
    },
  )
  requested_profiles = { system = var.system_size, user = var.user_size }

  requested_counts = var.node_counts

  # Networking assigns and approves the CIDRs. No CIDR or invented segment exists here.
  # Design-only contract: execution is not implemented or authorized by this module.
  design_only = var.proposal_mode == "DESIGN_WITHOUT_AWS_ACCOUNT"
  networking  = try(var.reviewed_execution.networking, null)
  # Stage 1: approved CIDRs + approval reference create the VPC and subnets.
  networking_ready = try(!local.design_only && var.reviewed_execution != null && local.networking != null && trimspace(local.networking.approval_reference) != "", false)
  # Stage 2: connectivity can only be attested once the VPC exists; the cluster
  # and everything attached to it waits for it (no circular dependency).
  connectivity_ready = try(local.networking_ready && local.networking.connectivity.routing_reviewed && local.networking.connectivity.private_api_reachable && local.networking.connectivity.dns_reviewed && local.networking.connectivity.registry_sts_eks_reachable, false)
  # Identity tags win over reviewed tags so they cannot be overridden.
  network_tags = merge(try(var.reviewed_execution.tags, {}), { Team = var.team_id, ApplicationCode = var.application_code, Environment = var.environment })

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
      error_message = "NETWORKING_PENDING: draft files may be reviewed; terraform plan/apply are blocked until Networking assigns and approves the VPC and subnet CIDRs."
    }
  }
}

# Modules use an inherited provider. None has an instance in this draft.

module "networking" {
  source       = "./modules/aws/networking"
  count        = local.networking_ready ? 1 : 0
  name         = module.naming.names.vpc
  subnet_names = module.naming.subnet_names
  region       = var.region
  networking   = terraform_data.networking_gate.output.networking
  tags         = local.network_tags
  depends_on   = [terraform_data.networking_gate]
}

# Advisory: the VPC may exist while Networking reviews routing/DNS/egress.
check "connectivity_review" {
  assert {
    condition     = !local.networking_ready || local.connectivity_ready
    error_message = "CONNECTIVITY_PENDING: VPC and subnets may be created; EKS, node groups and add-ons wait until Networking attests routing, private API, DNS and ECR/S3/STS/EKS reachability."
  }
}

module "iam" {
  source             = "./modules/aws/iam"
  count              = local.connectivity_ready ? 1 : 0
  name               = try(terraform_data.networking_gate.output.execution.resource_prefix, null)
  pod_identity_roles = try(var.reviewed_execution.pod_identity_roles, {})
  tags               = try(var.reviewed_execution.tags, {})
  depends_on         = [terraform_data.networking_gate, module.networking]
}
module "security_groups" {
  source                = "./modules/aws/security-groups"
  count                 = local.connectivity_ready ? 1 : 0
  name                  = try(terraform_data.networking_gate.output.execution.resource_prefix, null)
  vpc_id                = module.networking[0].vpc_id
  tags                  = try(var.reviewed_execution.tags, {})
  rules                 = try(var.reviewed_execution.security_group_rules, {})
  external_destinations = try(var.reviewed_execution.external_destinations, {})
  depends_on            = [terraform_data.networking_gate]
}
module "eks" {
  source                          = "./modules/aws/eks"
  count                           = local.connectivity_ready ? 1 : 0
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
  count        = local.connectivity_ready ? 1 : 0
  cluster_name = module.eks[0].name
  addons       = try({ for name, addon in var.reviewed_execution.addons : name => addon if name != "coredns" }, {})
  tags         = try(var.reviewed_execution.tags, {})
  depends_on   = [terraform_data.networking_gate]
}
module "nodegroups" {
  source             = "./modules/aws/nodegroups"
  count              = local.connectivity_ready ? 1 : 0
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
  count        = local.connectivity_ready ? 1 : 0
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
  subnet_counts = {
    cluster = length(try(local.networking.cluster_subnet_cidrs, []))
    node    = length(try(local.networking.node_subnet_cidrs, []))
  }
}
