locals {
  active          = var.enabled && local.catalog.networking.conformity == "approved"
  catalog         = yamldecode(file(var.catalog_path)).eks
  required_addons = toset(["vpc-cni", "kube-proxy", "coredns"])
}
resource "terraform_data" "approval" {
  count = var.enabled ? 1 : 0
  input = { catalogue_commit = var.catalog_commit_sha, catalogue_digest = filesha256(var.catalog_path), approval = var.approvals.reference }
  lifecycle {
    precondition {
      condition     = local.catalog.schema_version == 1 && local.catalog.configuration_model == "system_user_profiles" && filesha256(var.catalog_path) == var.catalog_sha256
      error_message = "The reviewed schema/model and exact catalogue digest are required."
    }
    precondition {
      condition     = var.approvals.generation && var.approvals.provisioning && var.approvals.technical_compatibility && var.approvals.managed_cluster_sg_review && trimspace(var.approvals.reference) != ""
      error_message = "Independent explicit approvals and review of EKS-managed SG defaults are required."
    }
    precondition {
      condition     = local.catalog.networking.conformity == "approved" && try(local.catalog.networking.approved_options[var.network_option_id].vpc_id == var.vpc_id && toset(local.catalog.networking.approved_options[var.network_option_id].cluster_subnet_ids) == toset(var.cluster_subnet_ids) && toset(local.catalog.networking.approved_options[var.network_option_id].node_subnet_ids) == toset(var.node_subnet_ids), false)
      error_message = "Networking is pending or the selected segments do not match the approved catalogue option."
    }
    precondition {
      condition     = length(setsubtract(local.required_addons, toset(keys(var.addons)))) == 0
      error_message = "Explicit versions and ownership for VPC CNI, kube-proxy and CoreDNS are required."
    }
    precondition {
      condition     = alltrue(flatten([for role in ["system", "user"] : [anytrue([for r in values(var.rules) : r.relation == "eks-api" && r.source == role && r.destination == "control_plane" && r.protocol == "tcp" && r.from_port == 443 && r.to_port == 443]), anytrue([for r in values(var.rules) : r.relation == "eks-kubelet" && r.source == "control_plane" && r.destination == role && r.protocol == "tcp" && r.from_port == 10250 && r.to_port == 10250])]]))
      error_message = "Separately approved EKS API/kubelet initiator flows for both roles are missing."
    }
  }
}
