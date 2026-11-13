locals {
  # Reuse the existing central policy and pure naming module, not a second table.
  naming_policy = jsondecode(file("${path.module}/../../../eks/naming/aws.json"))
  # Operation keys (Terraform-safe) and their IAM/session spelling.
  operations = {
    inspect     = "inspect"
    bootstrap   = "bootstrap"
    state_read  = "state-read"
    state_write = "state-write"
  }
  workspace_id  = var.workspace.id
  expected_path = "workspaces/${var.authorized_team_id}/terraform/aws/${var.workspace.environment}/${local.workspace_id}/main.tf"
  # ONE bucket per workspace: names.s3 with the INSTANCE sequence (eks-02 -> ...02).
  bucket     = module.workspace_naming.names.s3
  bucket_arn = "arn:aws:s3:::${local.bucket}"
  state_key  = "states/${var.authorized_team_id}/aws/${var.workspace.environment}/${local.workspace_id}/terraform.tfstate"
  lock_key   = "${local.state_key}.tflock"
  state_arn  = "${local.bucket_arn}/${local.state_key}"
  lock_arn   = "${local.bucket_arn}/${local.lock_key}"
  role_names = { for key, op in local.operations : key => "${local.bucket}-s3backend-${op}" }
  role_paths = { for key, op in local.operations : key => "/adp/s3-backend/${op}/" }
  # Shared per-operation ceilings created by the foundation (bound to role tags).
  boundary_arns = { for key, op in local.operations : key => "arn:aws:iam::${var.backend.account_id}:policy/adp/s3-backend/boundary/adp-s3-backend-${op}-boundary" }
  ownership_tags = {
    ManagedBy   = "Terraform"
    Ownership   = "s3-backend-access"
    Team        = var.authorized_team_id
    Instance    = local.workspace_id
    Bucket      = local.bucket
    Environment = var.backend.environment
  }
}

module "workspace_naming" {
  source      = "../../../eks/modules/naming"
  policy      = local.naming_policy
  team_id     = var.workspace.team_id
  environment = var.workspace.environment
  region      = var.workspace.region
  sequence    = var.workspace.sequence
}
