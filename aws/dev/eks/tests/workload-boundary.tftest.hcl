# Offline (mock provider, command = plan): workload boundary and AdpInstance tag. Run: terraform init -backend=false && terraform test
mock_provider "aws" {
  mock_data "aws_caller_identity" { defaults = { account_id = "123456789012" } }
  mock_data "aws_region" { defaults = { region = "us-east-1", name = "us-east-1" } }
  mock_data "aws_partition" { defaults = { partition = "aws" } }
  mock_data "aws_availability_zones" { defaults = { names = ["us-east-1a", "us-east-1b"] } }
  mock_data "aws_ssm_parameter" { defaults = { value = "ami-0123456789abcdef0" } }
  mock_resource "aws_iam_role" { defaults = { arn = "arn:aws:iam::123456789012:role/mock" } }
  mock_resource "aws_eks_cluster" { defaults = { arn = "arn:aws:eks:us-east-1:123456789012:cluster/mock" } }
  mock_resource "aws_instance" { defaults = { arn = "arn:aws:ec2:us-east-1:123456789012:instance/i-0123" } }
  mock_data "aws_eks_addon_version" { defaults = { version = "v1.3.0-eksbuild.1" } }
}

variables {
  team_id            = "D004"
  application_code   = "adp-eks"
  environment        = "dev"
  region             = "us-east-1"
  sequence           = 1
  kubernetes_version = "1.35"
  system_size        = "M"
  user_size          = "S"
  node_counts = {
    system = { minimum = 1, desired = 1, maximum = 2 }
    user   = { minimum = 1, desired = 1, maximum = 2 }
  }
  proposal_mode = "EKS_CLUSTER"
  reviewed_execution = {
    aws_account_id = "123456789012"
    networking = {
      vpc_cidr             = "10.102.0.0/16"
      cluster_subnet_cidrs = ["10.102.0.0/24", "10.102.1.0/24"]
      node_subnet_cidrs    = ["10.102.10.0/24", "10.102.11.0/24"]
      public_subnet_cidrs  = ["10.102.20.0/24"]
      approval_reference   = "TEST"
    }
    access = {
      platform_admin_role_arns = ["arn:aws:iam::123456789012:role/adp-platform-engineer"]
      bot_assumer_arns         = ["arn:aws:iam::123456789012:role/adp-k8s-bot-broker"]
    }
    pod_identity_roles  = { app = { policy_json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::x/y\"}]}" } }
    deletion_protection = false
  }
}


run "composition_plans_with_boundary" {
  command = plan
  variables { reviewed_execution = merge(var.reviewed_execution, { workload_permissions_boundary_arn = "arn:aws:iam::123456789012:policy/adp/boundary/adp-workload-boundary" }) }
  expect_failures = [check.connectivity_review]
}

run "composition_plans_without_boundary" {
  command         = plan
  expect_failures = [check.connectivity_review]
}

run "foreign_boundary_rejected" {
  command = plan
  variables { reviewed_execution = merge(var.reviewed_execution, { workload_permissions_boundary_arn = "arn:aws:iam::123456789012:policy/AdministratorAccess" }) }
  expect_failures = [var.reviewed_execution]
}

run "iam_roles_carry_the_boundary" {
  command = plan
  module { source = "./modules/aws/iam" }
  variables {
    name                 = "eksue1d004dev01"
    tags                 = { Team = "D004", ApplicationCode = "adp-eks", Environment = "dev", AdpInstance = "eksue1d004dev01" }
    pod_identity_roles   = var.reviewed_execution.pod_identity_roles
    permissions_boundary = "arn:aws:iam::123456789012:policy/adp/boundary/adp-workload-boundary"
  }
  assert {
    condition     = aws_iam_role.cluster.permissions_boundary == "arn:aws:iam::123456789012:policy/adp/boundary/adp-workload-boundary" && alltrue([for r in values(aws_iam_role.nodes) : r.permissions_boundary == "arn:aws:iam::123456789012:policy/adp/boundary/adp-workload-boundary"]) && alltrue([for r in values(aws_iam_role.pod_identity) : r.permissions_boundary == "arn:aws:iam::123456789012:policy/adp/boundary/adp-workload-boundary"])
    error_message = "every IAM role must carry the workload boundary"
  }
}

run "iam_roles_without_boundary_by_default" {
  command = plan
  module { source = "./modules/aws/iam" }
  variables {
    name = "eksue1d004dev01"
    tags = { Team = "D004", ApplicationCode = "adp-eks", Environment = "dev", AdpInstance = "eksue1d004dev01" }
  }
  assert {
    condition     = aws_iam_role.cluster.permissions_boundary == null
    error_message = "null keeps the previous behaviour"
  }
}

run "access_roles_carry_the_boundary" {
  command = plan
  module { source = "./modules/aws/access" }
  variables {
    name                      = "eksue1d004dev01"
    team_id                   = "D004"
    cluster_name              = "eksue1d004dev01"
    cluster_arn               = "arn:aws:eks:us-east-1:123456789012:cluster/eksue1d004dev01"
    cluster_security_group_id = "sg-0123456789abcdef0"
    vpc_id                    = "vpc-0123456789abcdef0"
    subnet_id                 = "subnet-0123456789abcdef0"
    platform_admin_role_arns  = var.reviewed_execution.access.platform_admin_role_arns
    bot_assumer_arns          = var.reviewed_execution.access.bot_assumer_arns
    tags                      = { Team = "D004", ApplicationCode = "adp-eks", Environment = "dev", AdpInstance = "eksue1d004dev01" }
    permissions_boundary      = "arn:aws:iam::123456789012:policy/adp/boundary/adp-workload-boundary"
  }
  assert {
    condition     = aws_iam_role.bot.permissions_boundary == "arn:aws:iam::123456789012:policy/adp/boundary/adp-workload-boundary" && aws_iam_role.tools.permissions_boundary == "arn:aws:iam::123456789012:policy/adp/boundary/adp-workload-boundary" && aws_iam_role.jump.permissions_boundary == "arn:aws:iam::123456789012:policy/adp/boundary/adp-workload-boundary"
    error_message = "bot, tools and jump roles must carry the workload boundary"
  }
  assert {
    condition     = aws_instance.jump.tags["AdpInstance"] == "eksue1d004dev01" && aws_security_group.jump.tags["AdpInstance"] == "eksue1d004dev01"
    error_message = "instance tag must reach the jump host resources"
  }
}

run "launch_template_instances_keep_previous_tags" {
  command = plan
  module { source = "./modules/aws/nodegroups" }
  variables {
    cluster_name            = "eksue1d004dev01"
    kubernetes_version      = "1.35"
    catalog                 = merge({ for k, v in yamldecode(file("../eks.yaml")).eks : k => v if k != "environments" }, { schema_version = 1, nodegroups = yamldecode(file("../eks.yaml")).eks.environments.dev.nodegroups })
    subnet_ids              = ["subnet-0123456789abcdef0"]
    node_role_arns          = { system = "arn:aws:iam::123456789012:role/a", user = "arn:aws:iam::123456789012:role/b" }
    selections              = { system = { size = "M", capacity_type = "ON_DEMAND", minimum = 1, desired = 1, maximum = 2, release_version = null, taints = [] }, user = { size = "S", capacity_type = "ON_DEMAND", minimum = 1, desired = 1, maximum = 2, release_version = null, taints = [] } }
    node_security_group_ids = { system = "sg-0123456789abcdef0", user = "sg-0123456789abcdef1" }
    tags                    = { Team = "D004", ApplicationCode = "adp-eks", Environment = "dev", AdpInstance = "eksue1d004dev01" }
  }
  assert {
    condition     = alltrue([for lt in values(aws_launch_template.role) : !contains(keys(one(lt.tag_specifications).tags), "AdpInstance") && lt.tags["AdpInstance"] == "eksue1d004dev01"])
    error_message = "AdpInstance on the template resource only, never in instance tag_specifications"
  }
}
