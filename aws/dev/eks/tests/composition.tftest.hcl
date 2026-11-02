mock_provider "aws" {
  mock_data "aws_partition" { defaults = { partition = "aws" } }
  mock_data "aws_region" { defaults = { region = "test-region-1" } }
  mock_data "aws_vpc" { defaults = { id = "vpc-00000001", enable_dns_support = true, enable_dns_hostnames = true } }
  mock_data "aws_subnet" { defaults = { vpc_id = "vpc-00000001", map_public_ip_on_launch = false } }
  mock_resource "aws_launch_template" { defaults = { latest_version = 1 } }
}
variables {
  catalog_path       = "fixtures/catalog-network-approved.synthetic.yaml"
  catalog_commit_sha = "0000000000000000000000000000000000000000"
  catalog_sha256     = filesha256("fixtures/catalog-network-approved.synthetic.yaml")
  name               = "synthetic"
  region             = "test-region-1"
  kubernetes_version = "1.99"
  vpc_id             = "vpc-00000001"
  cluster_subnet_ids = ["subnet-00000001", "subnet-00000002"]
  node_subnet_ids    = ["subnet-00000001", "subnet-00000002"]
  network_option_id  = "synthetic-network"
  connectivity       = { "approval_reference" : "SYNTHETIC-NETWORK-ONLY", "routing_reviewed" : true, "private_api_reachable" : true, "dns_reviewed" : true, "registry_sts_eks_reachable" : true }
  kms_key_arn        = "arn:aws:kms:test-region-1:000000000000:key/00000000-0000-0000-0000-000000000000"
  log_retention_days = 30
  tags               = {}
  selections         = { "system" : { "size" : "S", "capacity_type" : "ON_DEMAND", "minimum" : 1, "desired" : 1, "maximum" : 2, "release_version" : "1.99.0-synthetic" }, "user" : { "size" : "S", "capacity_type" : "ON_DEMAND", "minimum" : 1, "desired" : 1, "maximum" : 2, "release_version" : "1.99.0-synthetic" } }
  addons             = { "vpc-cni" : { "version" : "v1.99.0-eksbuild.1", "ownership_approved" : true, "service_account_role_arn" : "arn:aws:iam::000000000000:role/synthetic-cni-irsa" }, "kube-proxy" : { "version" : "v1.99.0-eksbuild.1", "ownership_approved" : true }, "coredns" : { "version" : "v1.99.0-eksbuild.1", "ownership_approved" : true } }
  root_volumes       = { "system" : { "size_gib" : 20, "kms_key_arn" : "arn:aws:kms:test-region-1:000000000000:key/00000000-0000-0000-0000-000000000000" }, "user" : { "size_gib" : 20, "kms_key_arn" : "arn:aws:kms:test-region-1:000000000000:key/00000000-0000-0000-0000-000000000000" } }
  rules              = { "system-eks-api" : { "relation" : "eks-api", "source" : "system", "destination" : "control_plane", "protocol" : "tcp", "from_port" : 443, "to_port" : 443, "approval_reference" : "SYNTHETIC-ONLY" }, "system-eks-kubelet" : { "relation" : "eks-kubelet", "source" : "control_plane", "destination" : "system", "protocol" : "tcp", "from_port" : 10250, "to_port" : 10250, "approval_reference" : "SYNTHETIC-ONLY" }, "user-eks-api" : { "relation" : "eks-api", "source" : "user", "destination" : "control_plane", "protocol" : "tcp", "from_port" : 443, "to_port" : 443, "approval_reference" : "SYNTHETIC-ONLY" }, "user-eks-kubelet" : { "relation" : "eks-kubelet", "source" : "control_plane", "destination" : "user", "protocol" : "tcp", "from_port" : 10250, "to_port" : 10250, "approval_reference" : "SYNTHETIC-ONLY" } }
}

run "disabled_by_default" {
  command = plan
  module { source = "../examples/composition" }
  variables {

  }
  assert {
    condition     = output.cluster == null && output.nodegroups == null && length(module.eks) == 0 && length(module.nodegroups) == 0
    error_message = "Disabled reference composition must create no cluster or nodes."
  }
}

run "approvals_required" {
  command = plan
  module { source = "../examples/composition" }
  variables {
    enabled = true
  }
  expect_failures = [terraform_data.approval]
}

run "pending_networking_blocks" {
  command = plan
  module { source = "../examples/composition" }
  variables {
    enabled        = true
    approvals      = { "generation" : true, "provisioning" : true, "technical_compatibility" : true, "managed_cluster_sg_review" : true, "reference" : "SYNTHETIC-ONLY" }
    catalog_path   = "fixtures/catalog.synthetic.yaml"
    catalog_sha256 = filesha256("fixtures/catalog.synthetic.yaml")
  }
  expect_failures = [terraform_data.approval]
}

run "reference_modules_connect" {
  command = plan
  module { source = "../examples/composition" }
  variables {
    enabled   = true
    approvals = { "generation" : true, "provisioning" : true, "technical_compatibility" : true, "managed_cluster_sg_review" : true, "reference" : "SYNTHETIC-ONLY" }
  }
  override_data {
    target = module.networking[0].data.aws_subnet.approved["subnet-00000001"]
    values = { id = "subnet-00000001", vpc_id = "vpc-00000001", availability_zone_id = "synthetic-az1", map_public_ip_on_launch = false }
  }
  override_data {
    target = module.networking[0].data.aws_subnet.approved["subnet-00000002"]
    values = { id = "subnet-00000002", vpc_id = "vpc-00000001", availability_zone_id = "synthetic-az2", map_public_ip_on_launch = false }
  }
  assert {
    condition     = output.nodegroups.system.instance_type == "synthetic.small" && output.nodegroups.user.instance_type == "synthetic.medium"
    error_message = "Reference composition must resolve role profiles solely from the synthetic catalogue."
  }
  assert {
    condition     = length(module.eks) == 1 && length(module.nodegroups) == 1 && length(module.foundation_addons) == 1 && length(module.dns_addon) == 1
    error_message = "Reference graph must compose the isolated owners exactly once."
  }
}
