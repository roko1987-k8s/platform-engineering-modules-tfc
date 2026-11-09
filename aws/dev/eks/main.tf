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

  # Modes. DESIGN_WITHOUT_AWS_ACCOUNT never creates anything. NETWORKING_ONLY
  # creates the VPC, subnets and egress. EKS_CLUSTER adds the cluster on top of
  # the same networking instance (module.networking[0] in both modes), so moving
  # from NETWORKING_ONLY to EKS_CLUSTER never replaces the network.
  execution    = var.proposal_mode != "DESIGN_WITHOUT_AWS_ACCOUNT"
  cluster_mode = var.proposal_mode == "EKS_CLUSTER"

  # Networking assigns and approves the CIDRs. No CIDR or invented segment exists here.
  networking       = try(var.reviewed_execution.networking, null)
  networking_ready = try(local.execution && var.reviewed_execution != null && local.networking != null && trimspace(local.networking.approval_reference) != "", false)
  # Connectivity can only be attested once the VPC exists (no circular dependency).
  connectivity_ready = try(local.networking_ready && local.networking.connectivity.routing_reviewed && local.networking.connectivity.private_api_reachable && local.networking.connectivity.dns_reviewed && local.networking.connectivity.registry_sts_eks_reachable, false)
  # Cluster-only inputs; NETWORKING_ONLY never requires EKS/IAM/KMS values.
  cluster_inputs_complete = try(var.reviewed_execution.resource_prefix != null && var.reviewed_execution.kms_key_arn != null && var.reviewed_execution.log_retention_days != null && var.reviewed_execution.root_volumes != null, false)
  cluster_ready           = local.cluster_mode && local.connectivity_ready && local.cluster_inputs_complete

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
# Preconditions use only variables and locals, so they are evaluated during plan
# and stop it before any change. Modules intentionally do not consume this
# resource's output: a changed input would make their arguments unknown and force
# replacement of networking or the cluster.
resource "terraform_data" "networking_gate" {
  input = { workspace = local.workspace, mode = var.proposal_mode }
  lifecycle {
    precondition {
      condition     = local.networking_ready
      error_message = "NETWORKING_PENDING: draft files may be reviewed; terraform plan/apply are blocked until Networking assigns and approves the VPC and subnet CIDRs."
    }
    precondition {
      condition     = !local.cluster_mode || local.connectivity_ready
      error_message = "CONNECTIVITY_PENDING: EKS_CLUSTER requires Networking to attest routing, private API, DNS and ECR/S3/STS/EKS reachability."
    }
    precondition {
      condition     = !local.cluster_mode || local.cluster_inputs_complete
      error_message = "EXECUTION_INPUT_INCOMPLETE: EKS_CLUSTER requires resource_prefix, kms_key_arn, log_retention_days and root_volumes."
    }
  }
}

# The credentials Terraform received must belong to the reviewed target account.
data "aws_caller_identity" "current" {
  count = local.networking_ready ? 1 : 0
}
resource "terraform_data" "account_gate" {
  count = local.networking_ready ? 1 : 0
  input = var.reviewed_execution.aws_account_id
  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current[0].account_id == var.reviewed_execution.aws_account_id
      error_message = "ACCOUNT_MISMATCH: the AWS credentials do not belong to the reviewed target account."
    }
  }
}

# Modules use an inherited provider. None has an instance in design mode.

module "networking" {
  source       = "./modules/aws/networking"
  count        = local.networking_ready ? 1 : 0
  name         = module.naming.names.vpc
  subnet_names = module.naming.subnet_names
  region       = var.region
  networking   = local.networking
  tags         = local.network_tags
}

# Advisory in NETWORKING_ONLY: the network may exist while Networking reviews it.
check "connectivity_review" {
  assert {
    condition     = !local.networking_ready || local.connectivity_ready
    error_message = "CONNECTIVITY_PENDING: VPC and subnets may be created; EKS, node groups and add-ons wait until Networking attests routing, private API, DNS and ECR/S3/STS/EKS reachability."
  }
}

module "iam" {
  source             = "./modules/aws/iam"
  count              = local.cluster_ready ? 1 : 0
  name               = var.reviewed_execution.resource_prefix
  pod_identity_roles = try(var.reviewed_execution.pod_identity_roles, {})
  tags               = try(var.reviewed_execution.tags, {})
}
module "security_groups" {
  source                = "./modules/aws/security-groups"
  count                 = local.cluster_ready ? 1 : 0
  name                  = var.reviewed_execution.resource_prefix
  vpc_id                = module.networking[0].vpc_id
  tags                  = try(var.reviewed_execution.tags, {})
  rules                 = try(var.reviewed_execution.security_group_rules, {})
  external_destinations = try(var.reviewed_execution.external_destinations, {})
}
module "eks" {
  source                          = "./modules/aws/eks"
  count                           = local.cluster_ready ? 1 : 0
  name                            = module.naming.names.eks
  catalog                         = local.catalog
  kubernetes_version              = var.kubernetes_version
  region                          = var.region
  role_arn                        = module.iam[0].cluster_role_arn
  subnet_ids                      = module.networking[0].cluster_subnet_ids
  control_plane_security_group_id = module.security_groups[0].security_group_ids.control_plane
  kms_key_arn                     = var.reviewed_execution.kms_key_arn
  log_retention_days              = var.reviewed_execution.log_retention_days
  tags                            = try(var.reviewed_execution.tags, {})
}
module "foundation_addons" {
  source       = "./modules/aws/addons"
  count        = local.cluster_ready ? 1 : 0
  cluster_name = module.eks[0].name
  addons       = try({ for name, addon in var.reviewed_execution.addons : name => addon if name != "coredns" }, {})
  tags         = try(var.reviewed_execution.tags, {})
}
module "nodegroups" {
  source             = "./modules/aws/nodegroups"
  count              = local.cluster_ready ? 1 : 0
  cluster_name       = module.eks[0].name
  kubernetes_version = var.kubernetes_version
  catalog            = local.catalog
  subnet_ids         = module.networking[0].node_subnet_ids
  node_role_arns     = module.iam[0].node_role_arns
  security_group_ids = module.security_groups[0].security_group_ids
  selections         = local.selections
  root_volumes       = var.reviewed_execution.root_volumes
  tags               = try(var.reviewed_execution.tags, {})
  depends_on         = [module.foundation_addons]
}
module "dns_addon" {
  source       = "./modules/aws/addons"
  count        = local.cluster_ready ? 1 : 0
  cluster_name = module.eks[0].name
  addons       = try({ for name, addon in var.reviewed_execution.addons : name => addon if name == "coredns" }, {})
  tags         = try(var.reviewed_execution.tags, {})
  depends_on   = [module.nodegroups]
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
    public  = length(try(local.networking.public_subnet_cidrs, []))
    cluster = length(try(local.networking.cluster_subnet_cidrs, []))
    node    = length(try(local.networking.node_subnet_cidrs, []))
  }
}
