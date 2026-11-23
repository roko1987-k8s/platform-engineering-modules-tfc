# Offline (mock provider, command = plan): what the internal NLB of the Istio gateway needs. Run: terraform init -backend=false && terraform test
mock_provider "aws" {
  mock_data "aws_availability_zones" { defaults = { names = ["us-east-1a", "us-east-1b"] } }
  mock_data "aws_region" { defaults = { region = "us-east-1", name = "us-east-1" } }
  mock_data "aws_partition" { defaults = { partition = "aws" } }
}

run "only_node_subnets_host_internal_load_balancers" {
  command = plan
  module { source = "./modules/aws/networking" }
  variables {
    name = "vpcue1d004dev01"
    subnet_names = {
      public  = ["vpcue1d004dev01-public-01"]
      cluster = ["vpcue1d004dev01-cluster-01", "vpcue1d004dev01-cluster-02"]
      node    = ["vpcue1d004dev01-node-01", "vpcue1d004dev01-node-02"]
    }
    region = "us-east-1"
    networking = {
      vpc_cidr             = "10.102.0.0/16"
      cluster_subnet_cidrs = ["10.102.0.0/24", "10.102.1.0/24"]
      node_subnet_cidrs    = ["10.102.10.0/24", "10.102.11.0/24"]
      public_subnet_cidrs  = ["10.102.20.0/24"]
      approval_reference   = "TEST"
    }
    tags = { Team = "D004", AdpInstance = "eksue1d004dev01" }
  }
  assert {
    condition     = alltrue([for name, s in aws_subnet.this : (lookup(s.tags, "kubernetes.io/role/internal-elb", "") == "1") == (s.tags["SubnetRole"] == "node")])
    error_message = "kubernetes.io/role/internal-elb=1 on node subnets only"
  }
  assert {
    condition     = alltrue([for s in values(aws_subnet.this) : !contains(keys(s.tags), "kubernetes.io/role/elb")])
    error_message = "No subnet is offered for internet-facing load balancers"
  }
}

run "controller_role_uses_the_upstream_policy_under_the_boundary" {
  command = plan
  module { source = "./modules/aws/iam" }
  variables {
    name                 = "eksue1d004dev01"
    tags                 = { Team = "D004", AdpInstance = "eksue1d004dev01" }
    lb_controller        = true
    permissions_boundary = "arn:aws:iam::123456789012:policy/adp/boundary/adp-workload-boundary"
  }
  assert {
    condition     = aws_iam_role.lb_controller[0].name == "eksue1d004dev01-lb-controller" && aws_iam_role.lb_controller[0].permissions_boundary == "arn:aws:iam::123456789012:policy/adp/boundary/adp-workload-boundary"
    error_message = "Controller role <names.eks>-lb-controller under the workload boundary"
  }
  assert {
    condition     = jsondecode(aws_iam_role.lb_controller[0].assume_role_policy).Statement[0].Principal.Service == "pods.eks.amazonaws.com"
    error_message = "Only EKS Pod Identity can assume the controller role"
  }
  assert {
    condition     = strcontains(aws_iam_role_policy.lb_controller[0].policy, "elbv2.k8s.aws/cluster")
    error_message = "Upstream controller policy (writes scoped by the elbv2.k8s.aws/cluster tag)"
  }
}

run "no_controller_role_unless_requested" {
  command = plan
  module { source = "./modules/aws/iam" }
  variables {
    name = "eksue1d004dev01"
    tags = {}
  }
  assert {
    condition     = length(aws_iam_role.lb_controller) == 0
    error_message = "lb_controller defaults to false in the IAM module"
  }
}
