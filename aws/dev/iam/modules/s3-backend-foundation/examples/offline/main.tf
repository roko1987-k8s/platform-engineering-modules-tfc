# Review-only wrapper. No backend, provider credentials or deployable defaults.
# Validate with Terraform mocks using tools/terraform/validate-s3-backend-access.py.
terraform {
  required_version = ">= 1.10, < 2.0"
}

variable "account_id" { type = string }
variable "region" { type = string }
variable "environment" { type = string }
variable "agent_principal_arn" { type = string }
variable "approval" { type = object({ revision = string, reference = string }) }

module "foundation" {
  source              = "../.."
  account_id          = var.account_id
  region              = var.region
  environment         = var.environment
  agent_principal_arn = var.agent_principal_arn
  approval            = var.approval
}

output "boundary_arns" { value = module.foundation.boundary_arns }
