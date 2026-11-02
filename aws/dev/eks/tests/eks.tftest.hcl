mock_provider "aws" {
  mock_data "aws_partition" { defaults = { partition = "aws" } }
  mock_data "aws_region" { defaults = { region = "test-region-1" } }
  mock_data "aws_vpc" { defaults = { id = "vpc-00000001", enable_dns_support = true, enable_dns_hostnames = true } }
  mock_data "aws_subnet" { defaults = { vpc_id = "vpc-00000001", map_public_ip_on_launch = false } }
  mock_resource "aws_launch_template" { defaults = { latest_version = 1 } }
}
variables {
  name                            = "synthetic"
  catalog                         = yamldecode(file("fixtures/catalog.synthetic.yaml")).eks
  kubernetes_version              = "1.99"
  region                          = "test-region-1"
  role_arn                        = "arn:aws:iam::000000000000:role/synthetic-cluster"
  subnet_ids                      = ["subnet-00000001", "subnet-00000002"]
  control_plane_security_group_id = "sg-00000001"
  kms_key_arn                     = "arn:aws:kms:test-region-1:000000000000:key/00000000-0000-0000-0000-000000000000"
  log_retention_days              = 30
  tags                            = {}
}
run "private_cluster" {
  command = plan
  module { source = "../modules/aws/eks" }

  assert {
    condition     = !aws_eks_cluster.this.vpc_config[0].endpoint_public_access && aws_eks_cluster.this.vpc_config[0].endpoint_private_access
    error_message = "No public endpoint."
  }
  assert {
    condition     = aws_eks_cluster.this.access_config[0].authentication_mode == "API" && !aws_eks_cluster.this.access_config[0].bootstrap_cluster_creator_admin_permissions
    error_message = "No implicit admin."
  }
  assert {
    condition     = aws_eks_cluster.this.deletion_protection
    error_message = "Deletion protection required."
  }
  assert {
    condition     = aws_cloudwatch_log_group.control_plane.retention_in_days == 30
    error_message = "Finite explicit log retention."
  }

}

run "uncatalogued_version" {
  command = plan
  module { source = "../modules/aws/eks" }
  variables {
    kubernetes_version = "1.98"
  }
  expect_failures = [var.kubernetes_version]

}

run "uncatalogued_region" {
  command = plan
  module { source = "../modules/aws/eks" }
  variables {
    region = "other-region"
  }
  expect_failures = [var.region]

}

run "unsupported_retention" {
  command = plan
  module { source = "../modules/aws/eks" }
  variables {
    log_retention_days = 0
  }
  expect_failures = [var.log_retention_days]

}

run "missing_kms" {
  command = plan
  module { source = "../modules/aws/eks" }
  variables {
    kms_key_arn = ""
  }
  expect_failures = [var.kms_key_arn]

}

run "provider_region_mismatch" {
  command = plan
  module { source = "../modules/aws/eks" }
  override_data {
    target = data.aws_region.current
    values = { region = "different-synthetic-region" }
  }
  expect_failures = [aws_eks_cluster.this]
}
