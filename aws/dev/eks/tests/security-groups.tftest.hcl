# Offline (mock provider, command = plan): own security groups and explicit rules. Run: terraform init -backend=false && terraform test
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
    deletion_protection = false
  }
}

run "composition_wires_the_base_catalogue" {
  command         = plan
  expect_failures = [check.connectivity_review]
  assert {
    condition     = toset(keys(output.security_groups.rules)) == toset(["100", "101", "103", "104", "110", "111", "112", "113"]) && output.security_groups.rules["103"].ports == ["80", "443"] && output.security_groups.rules["104"].ports == ["80", "443", "15021"] && output.security_groups.rules["100"].ports == ["443", "1025-65535"] && output.security_groups.rules["104"].sources == ["lb"]
    error_message = "One logical rule per RuleId with all its ports (102 pending ports)"
  }
}

run "composition_wires_the_load_balancer_controller" {
  command         = plan
  expect_failures = [check.connectivity_review]
  assert {
    condition     = output.load_balancer_controller.service_account == "aws-load-balancer-controller/aws-load-balancer-controller" && output.load_balancer_controller.cluster_name == "eksue1d004dev01"
    error_message = "Pod Identity association for the controller's service account"
  }
}

run "pod_identity_agent_not_in_reviewed_addons" {
  command = plan
  variables {
    reviewed_execution = merge(var.reviewed_execution, {
      addons = { "eks-pod-identity-agent" = { version = "v1.3.0-eksbuild.1", ownership_approved = true } }
    })
  }
  expect_failures = [terraform_data.networking_gate, check.connectivity_review]
}

run "custom_rule_outside_150_199_rejected" {
  command = plan
  module { source = "./modules/aws/security-groups" }
  variables {
    name                      = "sgue1d004dev01"
    rules_catalog             = yamldecode(file("../../../network/rules.yaml"))
    cluster_name              = "eksue1d004dev01"
    cluster_security_group_id = "sg-0aaaaaaaaaaaaaaaa"
    vpc_id                    = "vpc-0123456789abcdef0"
    tags                      = {}
    custom_rules = {
      late = { rule = "215", source = "system", destination = "user", protocol = "tcp", ports = ["9090"], approval_reference = "CHG-1" }
    }
  }
  expect_failures = [var.custom_rules]
}

run "own_groups_with_naming_and_tags" {
  command = plan
  module { source = "./modules/aws/security-groups" }
  variables {
    name                      = "sgue1d004dev01"
    rules_catalog             = yamldecode(file("../../../network/rules.yaml"))
    cluster_name              = "eksue1d004dev01"
    cluster_security_group_id = "sg-0aaaaaaaaaaaaaaaa"
    vpc_id                    = "vpc-0123456789abcdef0"
    jump_enabled              = true
    jump_security_group_id    = "sg-0bbbbbbbbbbbbbbbb"
    tags                      = { Team = "D004", ApplicationCode = "adp-eks", Environment = "dev", AdpInstance = "eksue1d004dev01" }
  }
  assert {
    condition     = toset([for sg in values(aws_security_group.role) : sg.name]) == toset(["sgue1d004dev01-system", "sgue1d004dev01-user", "sgue1d004dev01-ingress"])
    error_message = "Own groups are named <names.sg>-system/-user/-ingress"
  }
  assert {
    condition     = alltrue([for sg in values(aws_security_group.role) : sg.tags["AdpInstance"] == "eksue1d004dev01" && sg.tags["Team"] == "D004"])
    error_message = "Own groups carry the instance tags (executor roles act only on tagged resources)"
  }
  assert {
    condition     = toset([for r in values(aws_vpc_security_group_ingress_rule.rule) : r.tags["RuleId"]]) == toset(["100", "101", "103", "104", "110", "111", "112", "113"])
    error_message = "Every active catalogue rule has its ingress half, tagged with its RuleId (102 pending)"
  }
  assert {
    condition     = alltrue([for r in values(aws_vpc_security_group_ingress_rule.rule) : r.ip_protocol != "-1" || contains(["110", "111", "112", "113"], r.tags["RuleId"])])
    error_message = "Protocol -1 only for node to node (110-113)"
  }
  assert {
    condition     = length([for r in values(aws_vpc_security_group_ingress_rule.rule) : r if r.tags["RuleId"] == "100"]) == 4 && length([for r in values(aws_vpc_security_group_ingress_rule.rule) : r if r.tags["RuleId"] == "101" && r.from_port == 443]) == 2 && length([for r in values(aws_vpc_security_group_ingress_rule.rule) : r if r.tags["RuleId"] == "104"]) == 3
    error_message = "Each logical rule expands per source x destination x port range (100: 4, 101: 2, 104: 3)"
  }
  assert {
    condition     = length([for r in values(aws_vpc_security_group_ingress_rule.rule) : r if r.tags["RuleId"] == "103"]) == 2 && alltrue([for r in values(aws_vpc_security_group_ingress_rule.rule) : r.cidr_ipv4 == "0.0.0.0/0" if r.tags["RuleId"] == "103"])
    error_message = "103: any to the internal NLB on 80 and 443 only (the jump host is already covered by any)"
  }
  assert {
    condition     = length(aws_vpc_security_group_egress_rule.rule) == 5 && length([for r in values(aws_vpc_security_group_egress_rule.rule) : r if r.tags["RuleId"] == "104"]) == 3 && length([for r in values(aws_vpc_security_group_egress_rule.rule) : r if r.tags["RuleId"] == "103"]) == 2
    error_message = "Egress halves only on closed groups: NLB to the gateway pods (104) and jump host to the NLB (103)"
  }
  assert {
    condition     = length([for r in values(aws_vpc_security_group_ingress_rule.rule) : r if tonumber(r.tags["RuleId"]) >= 150]) == 0
    error_message = "No custom rule unless reviewed_execution brings one"
  }
}

run "custom_rule_in_reserved_range" {
  command = plan
  module { source = "./modules/aws/security-groups" }
  variables {
    name                      = "sgue1d004dev01"
    rules_catalog             = yamldecode(file("../../../network/rules.yaml"))
    cluster_name              = "eksue1d004dev01"
    cluster_security_group_id = "sg-0aaaaaaaaaaaaaaaa"
    vpc_id                    = "vpc-0123456789abcdef0"
    tags                      = { AdpInstance = "eksue1d004dev01" }
    custom_rules = {
      metrics = { rule = "150", source = "system", destination = "user", protocol = "tcp", ports = ["9090", "9100-9102"], approval_reference = "CHG-1" }
    }
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.rule["150-system-user-9090"].tags["RuleId"] == "150" && aws_vpc_security_group_ingress_rule.rule["150-system-user-9100-9102"].to_port == 9102
    error_message = "One custom rule with all its ports expands into one AWS rule per port range, same RuleId"
  }
}

run "custom_rule_any_protocol_rejected" {
  command = plan
  module { source = "./modules/aws/security-groups" }
  variables {
    name                      = "sgue1d004dev01"
    rules_catalog             = yamldecode(file("../../../network/rules.yaml"))
    cluster_name              = "eksue1d004dev01"
    cluster_security_group_id = "sg-0aaaaaaaaaaaaaaaa"
    vpc_id                    = "vpc-0123456789abcdef0"
    tags                      = {}
    custom_rules = {
      wide = { rule = "151", source = "system", destination = "user", protocol = "-1", ports = ["1-65535"], approval_reference = "CHG-1" }
    }
  }
  expect_failures = [var.custom_rules]
}

run "custom_rule_without_approval_rejected" {
  command = plan
  module { source = "./modules/aws/security-groups" }
  variables {
    name                      = "sgue1d004dev01"
    rules_catalog             = yamldecode(file("../../../network/rules.yaml"))
    cluster_name              = "eksue1d004dev01"
    cluster_security_group_id = "sg-0aaaaaaaaaaaaaaaa"
    vpc_id                    = "vpc-0123456789abcdef0"
    tags                      = {}
    custom_rules = {
      quiet = { rule = "152", source = "system", destination = "user", protocol = "tcp", ports = ["8080"], approval_reference = " " }
    }
  }
  expect_failures = [var.custom_rules]
}

run "nodes_use_their_own_group" {
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
    tags                    = { AdpInstance = "eksue1d004dev01" }
  }
  assert {
    condition     = aws_launch_template.role["system"].vpc_security_group_ids == toset(["sg-0123456789abcdef0"]) && aws_launch_template.role["user"].vpc_security_group_ids == toset(["sg-0123456789abcdef1"])
    error_message = "Each launch template sets exactly its own node group (EKS no longer attaches its group)"
  }
}

run "custom_rule_overlapping_ports_rejected" {
  command = plan
  module { source = "./modules/aws/security-groups" }
  variables {
    name                      = "sgue1d004dev01"
    rules_catalog             = yamldecode(file("../../../network/rules.yaml"))
    cluster_name              = "eksue1d004dev01"
    cluster_security_group_id = "sg-0aaaaaaaaaaaaaaaa"
    vpc_id                    = "vpc-0123456789abcdef0"
    tags                      = {}
    custom_rules = {
      overlap = { rule = "153", source = "system", destination = "user", protocol = "tcp", ports = ["8000-8100", "8080"], approval_reference = "CHG-1" }
    }
  }
  expect_failures = [var.custom_rules]
}

run "catalogue_never_has_any_as_destination" {
  command = plan
  module { source = "./modules/aws/security-groups" }
  variables {
    name = "sgue1d004dev01"
    rules_catalog = merge(yamldecode(file("../../../network/rules.yaml")), {
      rules = { "120" = { description = "wrong", sources = ["user"], destinations = ["any"], protocol = "tcp", ports = ["443"] } }
    })
    cluster_name              = "eksue1d004dev01"
    cluster_security_group_id = "sg-0aaaaaaaaaaaaaaaa"
    vpc_id                    = "vpc-0123456789abcdef0"
    tags                      = {}
  }
  expect_failures = [var.rules_catalog]
}
