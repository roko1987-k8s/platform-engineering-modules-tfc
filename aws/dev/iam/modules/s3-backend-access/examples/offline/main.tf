# Review-only wrapper. No backend, provider credentials or deployable defaults.
# Validate with Terraform mocks using tools/terraform/validate-s3-backend-access.py.
terraform {
  required_version = ">= 1.10, < 2.0"
}

variable "authorized_team_id" { type = string }
variable "workspace" {
  type = object({
    id     = string, team_id = string, application_code = string, environment = string,
    region = string, sequence = number,
    source = object({ repository = string, commit = string, path = string })
  })
}
variable "backend" {
  type = object({
    account_id          = string, region = string, environment = string,
    assignment_revision = string, approval_reference = string
  })
}
variable "foundation" {
  type = object({
    agent_principal_arn = string,
    boundary_arns       = object({ inspect = string, bootstrap = string, state_read = string, state_write = string }),
    revision            = string, approval_reference = string
  })
}

module "backend_access" {
  source             = "../.."
  authorized_team_id = var.authorized_team_id
  workspace          = var.workspace
  backend            = var.backend
  foundation         = var.foundation
}

output "resolved" { value = module.backend_access.resolved }
