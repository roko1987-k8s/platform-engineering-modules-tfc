mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { region = "test-region-1" }
  }
  mock_data "aws_vpc" {
    defaults = { id = "vpc-00000001", enable_dns_support = true, enable_dns_hostnames = true }
  }
  mock_data "aws_subnet" {
    defaults = { vpc_id = "vpc-00000001", map_public_ip_on_launch = false }
  }
  mock_resource "aws_launch_template" {
    defaults = { latest_version = 1 }
  }
}
variables {
  vpc_id             = "vpc-00000001"
  cluster_subnet_ids = ["subnet-00000001", "subnet-00000002"]
  node_subnet_ids    = ["subnet-00000001", "subnet-00000002"]
  conformity         = "approved"
  connectivity       = { "approval_reference" : "SYNTHETIC-TEST-ONLY", "routing_reviewed" : true, "private_api_reachable" : true, "dns_reviewed" : true, "registry_sts_eks_reachable" : true }
}
run "approved_existing_segments" {
  command = plan
  module { source = "../modules/aws/networking" }

  assert {
    condition     = output.vpc_id == "vpc-00000001"
    error_message = "Use an existing VPC, never create one."
  }
  override_data {
    target = data.aws_subnet.approved["subnet-00000001"]
    values = { id = "subnet-00000001", vpc_id = "vpc-00000001", availability_zone_id = "synthetic-az1", map_public_ip_on_launch = false }
  }
  override_data {
    target = data.aws_subnet.approved["subnet-00000002"]
    values = { id = "subnet-00000002", vpc_id = "vpc-00000001", availability_zone_id = "synthetic-az2", map_public_ip_on_launch = false }
  }

}

run "pending_networking" {
  command = plan
  module { source = "../modules/aws/networking" }
  variables {
    conformity = "pending"
  }
  expect_failures = [var.conformity]
  override_data {
    target = data.aws_subnet.approved["subnet-00000001"]
    values = { id = "subnet-00000001", vpc_id = "vpc-00000001", availability_zone_id = "synthetic-az1", map_public_ip_on_launch = false }
  }
  override_data {
    target = data.aws_subnet.approved["subnet-00000002"]
    values = { id = "subnet-00000002", vpc_id = "vpc-00000001", availability_zone_id = "synthetic-az2", map_public_ip_on_launch = false }
  }

}

run "missing_segments" {
  command = plan
  module { source = "../modules/aws/networking" }
  variables {
    cluster_subnet_ids = []
  }
  expect_failures = [var.cluster_subnet_ids]
  override_data {
    target = data.aws_subnet.approved["subnet-00000001"]
    values = { id = "subnet-00000001", vpc_id = "vpc-00000001", availability_zone_id = "synthetic-az1", map_public_ip_on_launch = false }
  }
  override_data {
    target = data.aws_subnet.approved["subnet-00000002"]
    values = { id = "subnet-00000002", vpc_id = "vpc-00000001", availability_zone_id = "synthetic-az2", map_public_ip_on_launch = false }
  }

}

run "duplicate_segments" {
  command = plan
  module { source = "../modules/aws/networking" }
  variables {
    node_subnet_ids = ["subnet-00000001", "subnet-00000001"]
  }
  expect_failures = [var.node_subnet_ids]
  override_data {
    target = data.aws_subnet.approved["subnet-00000001"]
    values = { id = "subnet-00000001", vpc_id = "vpc-00000001", availability_zone_id = "synthetic-az1", map_public_ip_on_launch = false }
  }
  override_data {
    target = data.aws_subnet.approved["subnet-00000002"]
    values = { id = "subnet-00000002", vpc_id = "vpc-00000001", availability_zone_id = "synthetic-az2", map_public_ip_on_launch = false }
  }

}

run "unreviewed_routing" {
  command = plan
  module { source = "../modules/aws/networking" }
  variables {
    connectivity = { "approval_reference" : "SYNTHETIC-TEST-ONLY", "routing_reviewed" : false, "private_api_reachable" : true, "dns_reviewed" : true, "registry_sts_eks_reachable" : true }
  }
  expect_failures = [var.connectivity]
  override_data {
    target = data.aws_subnet.approved["subnet-00000001"]
    values = { id = "subnet-00000001", vpc_id = "vpc-00000001", availability_zone_id = "synthetic-az1", map_public_ip_on_launch = false }
  }
  override_data {
    target = data.aws_subnet.approved["subnet-00000002"]
    values = { id = "subnet-00000002", vpc_id = "vpc-00000001", availability_zone_id = "synthetic-az2", map_public_ip_on_launch = false }
  }

}

run "wrong_vpc" {
  command = plan
  module { source = "../modules/aws/networking" }

  expect_failures = [data.aws_subnet.approved["subnet-00000002"]]
  override_data {
    target = data.aws_subnet.approved["subnet-00000001"]
    values = { id = "subnet-00000001", vpc_id = "vpc-00000001", availability_zone_id = "synthetic-az1", map_public_ip_on_launch = false }
  }
  override_data {
    target = data.aws_subnet.approved["subnet-00000002"]
    values = { id = "subnet-00000002", vpc_id = "vpc-00000003", availability_zone_id = "synthetic-az2", map_public_ip_on_launch = false }
  }

}

run "single_az" {
  command = plan
  module { source = "../modules/aws/networking" }

  expect_failures = [terraform_data.validation]
  override_data {
    target = data.aws_subnet.approved["subnet-00000001"]
    values = { id = "subnet-00000001", vpc_id = "vpc-00000001", availability_zone_id = "synthetic-az1", map_public_ip_on_launch = false }
  }
  override_data {
    target = data.aws_subnet.approved["subnet-00000002"]
    values = { id = "subnet-00000002", vpc_id = "vpc-00000001", availability_zone_id = "synthetic-az1", map_public_ip_on_launch = false }
  }

}

run "public_node_subnet" {
  command = plan
  module { source = "../modules/aws/networking" }

  expect_failures = [data.aws_subnet.approved["subnet-00000002"]]
  override_data {
    target = data.aws_subnet.approved["subnet-00000001"]
    values = { id = "subnet-00000001", vpc_id = "vpc-00000001", availability_zone_id = "synthetic-az1", map_public_ip_on_launch = false }
  }
  override_data {
    target = data.aws_subnet.approved["subnet-00000002"]
    values = { id = "subnet-00000002", vpc_id = "vpc-00000001", availability_zone_id = "synthetic-az2", map_public_ip_on_launch = true }
  }

}
