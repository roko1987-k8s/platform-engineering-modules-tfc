terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  backend "s3" {}
  required_providers {
    aws = { source = "hashicorp/aws", version = "= 6.20.0" }
  }
}

# Draft example only. No authenticated identity or approval is asserted here.
variable "reviewed_execution" {
  description = "Future reviewed execution inputs. Null preserves the incomplete draft; not an approval or credentials source."
  type = object({
    resource_prefix    = string
    catalog_commit_sha = string
    catalog_sha256     = string
    kms_key_arn        = string
    log_retention_days = number
    release_versions   = map(string)
    root_volumes       = map(object({ size_gib = number, kms_key_arn = string }))
    addons             = map(object({ version = string, ownership_approved = bool, configuration_values = optional(string), service_account_role_arn = optional(string), pod_identity_associations = optional(map(string), {}) }))
    tags               = map(string)
  })
  default = null
}

locals {
  workspace          = "@@WORKSPACE@@"
  team               = @@TEAM@@
  environment        = @@ENVIRONMENT@@
  deployment         = @@INSTANCE@@
  catalog_path       = "${path.module}/catalog.snapshot.json"
  catalog            = jsondecode(file(local.catalog_path)).eks
  requested_profiles = @@PROFILES@@

  requested_counts = @@COUNTS@@

  # Networking assigns and approves the CIDRs. No CIDR or invented segment exists.
  networking = {
    conformity           = "pending"
    option_id            = null
    vpc_cidr             = null
    public_subnet_cidrs  = null
    cluster_subnet_cidrs = null
    node_subnet_cidrs    = null
    approval_reference   = null
    connectivity         = null
  }
  networking_ready = local.networking.conformity == "approved" && local.catalog.networking.conformity == "approved" && local.networking.vpc_cidr != null && local.networking.public_subnet_cidrs != null && local.networking.cluster_subnet_cidrs != null && local.networking.node_subnet_cidrs != null && local.networking.approval_reference != null && local.networking.option_id != null && local.networking.connectivity != null

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
provider "aws" { region = one(local.catalog.cluster.allowed_regions) }

module "networking" {
  source       = "git::https://github.com/roko1987-k8s/platform-engineering-modules-tfc.git//aws/dev/eks/modules/aws/networking?ref=@@MODULE_SHA@@"
  count        = local.networking_ready ? 1 : 0
  name         = module.naming.names.vpc
  subnet_names = module.naming.subnet_names
  region       = one(local.catalog.cluster.allowed_regions)
  networking = {
    vpc_cidr             = terraform_data.networking_gate.output.networking.vpc_cidr
    public_subnet_cidrs  = terraform_data.networking_gate.output.networking.public_subnet_cidrs
    cluster_subnet_cidrs = terraform_data.networking_gate.output.networking.cluster_subnet_cidrs
    node_subnet_cidrs    = terraform_data.networking_gate.output.networking.node_subnet_cidrs
    approval_reference   = terraform_data.networking_gate.output.networking.approval_reference
    connectivity         = terraform_data.networking_gate.output.networking.connectivity
  }
  depends_on = [terraform_data.networking_gate]
}
module "iam" {
  source     = "git::https://github.com/roko1987-k8s/platform-engineering-modules-tfc.git//aws/dev/eks/modules/aws/iam?ref=@@MODULE_SHA@@"
  count      = local.networking_ready ? 1 : 0
  name       = try(terraform_data.networking_gate.output.execution.resource_prefix, null)
  tags       = try(var.reviewed_execution.tags, {})
  depends_on = [terraform_data.networking_gate, module.networking]
}
module "security_groups" {
  source = "git::https://github.com/roko1987-k8s/platform-engineering-modules-tfc.git//aws/dev/eks/modules/aws/security-groups?ref=@@MODULE_SHA@@"
  count  = local.networking_ready ? 1 : 0
  name   = try(terraform_data.networking_gate.output.execution.resource_prefix, null)
  vpc_id = module.networking[0].vpc_id
  tags   = try(var.reviewed_execution.tags, {})
  # No rules are supplied: existing empty/denied defaults are unchanged.
  depends_on = [terraform_data.networking_gate]
}
module "eks" {
  source                          = "git::https://github.com/roko1987-k8s/platform-engineering-modules-tfc.git//aws/dev/eks/modules/aws/eks?ref=@@MODULE_SHA@@"
  count                           = local.networking_ready ? 1 : 0
  name                            = module.naming.names.eks
  catalog                         = local.catalog
  kubernetes_version              = one(local.catalog.kubernetes.allowed_versions)
  region                          = one(local.catalog.cluster.allowed_regions)
  role_arn                        = module.iam[0].cluster_role_arn
  subnet_ids                      = module.networking[0].cluster_subnet_ids
  control_plane_security_group_id = module.security_groups[0].security_group_ids.control_plane
  kms_key_arn                     = try(terraform_data.networking_gate.output.execution.kms_key_arn, null)
  log_retention_days              = try(terraform_data.networking_gate.output.execution.log_retention_days, null)
  tags                            = try(var.reviewed_execution.tags, {})
  depends_on                      = [terraform_data.networking_gate]
}
module "foundation_addons" {
  source       = "git::https://github.com/roko1987-k8s/platform-engineering-modules-tfc.git//aws/dev/eks/modules/aws/addons?ref=@@MODULE_SHA@@"
  count        = local.networking_ready ? 1 : 0
  cluster_name = module.eks[0].name
  addons       = try({ for name, addon in var.reviewed_execution.addons : name => addon if name != "coredns" }, {})
  tags         = try(var.reviewed_execution.tags, {})
  depends_on   = [terraform_data.networking_gate]
}
module "nodegroups" {
  source             = "git::https://github.com/roko1987-k8s/platform-engineering-modules-tfc.git//aws/dev/eks/modules/aws/nodegroups?ref=@@MODULE_SHA@@"
  count              = local.networking_ready ? 1 : 0
  cluster_name       = module.eks[0].name
  kubernetes_version = one(local.catalog.kubernetes.allowed_versions)
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
  source       = "git::https://github.com/roko1987-k8s/platform-engineering-modules-tfc.git//aws/dev/eks/modules/aws/addons?ref=@@MODULE_SHA@@"
  count        = local.networking_ready ? 1 : 0
  cluster_name = module.eks[0].name
  addons       = try({ for name, addon in var.reviewed_execution.addons : name => addon if name == "coredns" }, {})
  tags         = try(var.reviewed_execution.tags, {})
  depends_on   = [terraform_data.networking_gate, module.nodegroups]
}

# Pure naming is available for review even while networking blocks deployment.
module "naming" {
  source      = "git::https://github.com/roko1987-k8s/platform-engineering-modules-tfc.git//aws/dev/eks/modules/naming?ref=@@MODULE_SHA@@"
  policy      = jsondecode(file("${path.module}/naming.snapshot.json"))
  region      = one(local.catalog.cluster.allowed_regions)
  team_id     = local.team
  environment = local.environment
  sequence    = @@SEQUENCE@@
  subnet_counts = {
    public  = try(length(local.networking.public_subnet_cidrs), 0)
    cluster = try(length(local.networking.cluster_subnet_cidrs), 0)
    node    = try(length(local.networking.node_subnet_cidrs), 0)
  }
}
output "proposed_names" {
  value       = module.naming.names
  description = "Names for review only; this draft creates no VPC or subnet."
}
