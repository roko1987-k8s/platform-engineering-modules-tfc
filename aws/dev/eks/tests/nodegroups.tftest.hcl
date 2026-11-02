mock_provider "aws" {
  mock_data "aws_partition" { defaults = { partition = "aws" } }
  mock_data "aws_region" { defaults = { region = "test-region-1" } }
  mock_data "aws_vpc" { defaults = { id = "vpc-00000001", enable_dns_support = true, enable_dns_hostnames = true } }
  mock_data "aws_subnet" { defaults = { vpc_id = "vpc-00000001", map_public_ip_on_launch = false } }
  mock_resource "aws_launch_template" { defaults = { latest_version = 1 } }
}
variables {
  root_volumes = {
    system = { size_gib = 20, kms_key_arn = "arn:aws:kms:test-region-1:000000000000:key/00000000-0000-0000-0000-000000000000" }
    user   = { size_gib = 20, kms_key_arn = "arn:aws:kms:test-region-1:000000000000:key/00000000-0000-0000-0000-000000000000" }
  }

  cluster_name       = "synthetic-cluster"
  kubernetes_version = "1.99"
  catalog            = yamldecode(file("fixtures/catalog.synthetic.yaml")).eks
  subnet_ids         = ["subnet-00000001", "subnet-00000002"]
  node_role_arns     = { "system" : "arn:aws:iam::000000000000:role/synthetic-system", "user" : "arn:aws:iam::000000000000:role/synthetic-user" }
  security_group_ids = { "system" : "sg-00000001", "user" : "sg-00000002" }
  tags               = {}
  selections         = { "system" : { "size" : "S", "capacity_type" : "ON_DEMAND", "minimum" : 1, "desired" : 1, "maximum" : 2, "release_version" : "1.99.0-synthetic" }, "user" : { "size" : "M", "capacity_type" : "ON_DEMAND", "minimum" : 1, "desired" : 2, "maximum" : 2, "release_version" : "1.99.0-synthetic" } }
}
run "profiles_resolve_per_role" {
  command = plan
  module { source = "../modules/aws/nodegroups" }

  assert {
    condition     = aws_eks_node_group.role["system"].instance_types == tolist(["synthetic.small"])
    error_message = "System S must resolve from its own catalogue."
  }
  assert {
    condition     = aws_eks_node_group.role["user"].instance_types == tolist(["synthetic.large"])
    error_message = "User M must resolve from its own catalogue."
  }
  assert {
    condition     = aws_launch_template.role["system"].metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 required."
  }
  assert {
    condition     = aws_launch_template.role["system"].vpc_security_group_ids == toset(["sg-00000001"])
    error_message = "Attach only the exact custom System SG."
  }
  assert {
    condition     = aws_eks_node_group.role["system"].ami_type == "AL2023_x86_64_STANDARD"
    error_message = "EKS manages AL2023 AMI/bootstrap without a second AMI source."
  }

}

run "unknown_profile" {
  command = plan
  module { source = "../modules/aws/nodegroups" }
  variables {
    selections = { "system" : { "size" : "XL", "capacity_type" : "ON_DEMAND", "minimum" : 1, "desired" : 1, "maximum" : 2, "release_version" : "1.99.0-synthetic" }, "user" : { "size" : "M", "capacity_type" : "ON_DEMAND", "minimum" : 1, "desired" : 2, "maximum" : 2, "release_version" : "1.99.0-synthetic" } }
  }
  expect_failures = [var.selections]

}

run "capacity_rejected" {
  command = plan
  module { source = "../modules/aws/nodegroups" }
  variables {
    selections = { "system" : { "size" : "S", "capacity_type" : "ON_DEMAND", "minimum" : 1, "desired" : 1, "maximum" : 2, "release_version" : "1.99.0-synthetic" }, "user" : { "size" : "M", "capacity_type" : "SPOT", "minimum" : 1, "desired" : 2, "maximum" : 2, "release_version" : "1.99.0-synthetic" } }
  }
  expect_failures = [var.selections]

}

run "lower_bound" {
  command = plan
  module { source = "../modules/aws/nodegroups" }
  variables {
    selections = { "system" : { "size" : "S", "capacity_type" : "ON_DEMAND", "minimum" : 0, "desired" : 1, "maximum" : 2, "release_version" : "1.99.0-synthetic" }, "user" : { "size" : "M", "capacity_type" : "ON_DEMAND", "minimum" : 1, "desired" : 2, "maximum" : 2, "release_version" : "1.99.0-synthetic" } }
  }
  expect_failures = [var.selections]

}

run "upper_bound" {
  command = plan
  module { source = "../modules/aws/nodegroups" }
  variables {
    selections = { "system" : { "size" : "S", "capacity_type" : "ON_DEMAND", "minimum" : 1, "desired" : 1, "maximum" : 2, "release_version" : "1.99.0-synthetic" }, "user" : { "size" : "M", "capacity_type" : "ON_DEMAND", "minimum" : 1, "desired" : 2, "maximum" : 3, "release_version" : "1.99.0-synthetic" } }
  }
  expect_failures = [var.selections]

}

run "unordered_desired" {
  command = plan
  module { source = "../modules/aws/nodegroups" }
  variables {
    selections = { "system" : { "size" : "S", "capacity_type" : "ON_DEMAND", "minimum" : 1, "desired" : 1, "maximum" : 2, "release_version" : "1.99.0-synthetic" }, "user" : { "size" : "M", "capacity_type" : "ON_DEMAND", "minimum" : 1, "desired" : 3, "maximum" : 2, "release_version" : "1.99.0-synthetic" } }
  }
  expect_failures = [var.selections]

}

run "fractional" {
  command = plan
  module { source = "../modules/aws/nodegroups" }
  variables {
    selections = { "system" : { "size" : "S", "capacity_type" : "ON_DEMAND", "minimum" : 1, "desired" : 1.5, "maximum" : 2, "release_version" : "1.99.0-synthetic" }, "user" : { "size" : "M", "capacity_type" : "ON_DEMAND", "minimum" : 1, "desired" : 2, "maximum" : 2, "release_version" : "1.99.0-synthetic" } }
  }
  expect_failures = [var.selections]

}

run "missing_release" {
  command = plan
  module { source = "../modules/aws/nodegroups" }
  variables {
    selections = { "system" : { "size" : "S", "capacity_type" : "ON_DEMAND", "minimum" : 1, "desired" : 1, "maximum" : 2, "release_version" : "" }, "user" : { "size" : "M", "capacity_type" : "ON_DEMAND", "minimum" : 1, "desired" : 2, "maximum" : 2, "release_version" : "1.99.0-synthetic" } }
  }
  expect_failures = [var.selections]

}

run "taint_invalid" {
  command = plan
  module { source = "../modules/aws/nodegroups" }
  variables {
    selections = { "system" : { "size" : "S", "capacity_type" : "ON_DEMAND", "minimum" : 1, "desired" : 1, "maximum" : 2, "release_version" : "1.99.0-synthetic" }, "user" : { "size" : "M", "capacity_type" : "ON_DEMAND", "minimum" : 1, "desired" : 2, "maximum" : 2, "release_version" : "1.99.0-synthetic", "taints" : [{ "key" : "bad key", "effect" : "NO_SCHEDULE" }] } }
  }
  expect_failures = [var.selections]

}

run "duplicate_taint" {
  command = plan
  module { source = "../modules/aws/nodegroups" }
  variables {
    selections = { "system" : { "size" : "S", "capacity_type" : "ON_DEMAND", "minimum" : 1, "desired" : 1, "maximum" : 2, "release_version" : "1.99.0-synthetic" }, "user" : { "size" : "M", "capacity_type" : "ON_DEMAND", "minimum" : 1, "desired" : 2, "maximum" : 2, "release_version" : "1.99.0-synthetic", "taints" : [{ "key" : "test", "effect" : "NO_SCHEDULE" }, { "key" : "test", "effect" : "NO_SCHEDULE" }] } }
  }
  expect_failures = [var.selections]

}

run "missing_role" {
  command = plan
  module { source = "../modules/aws/nodegroups" }
  variables {
    selections = { "system" : { "size" : "S", "capacity_type" : "ON_DEMAND", "minimum" : 1, "desired" : 1, "maximum" : 2, "release_version" : "1.99.0-synthetic" } }
  }
  expect_failures = [var.selections]

}

run "aggregate_rejected" {
  command = plan
  module { source = "../modules/aws/nodegroups" }
  variables {
    catalog = merge(yamldecode(file("fixtures/catalog.synthetic.yaml")).eks, { nodegroups = merge(yamldecode(file("fixtures/catalog.synthetic.yaml")).eks.nodegroups, { limits = { max_total_nodes = 3 } }) })
  }
  expect_failures = [var.selections]

}

run "shared_security_group_rejected" {
  command = plan
  module { source = "../modules/aws/nodegroups" }
  variables { security_group_ids = { system = "sg-00000001", user = "sg-00000001" } }
  expect_failures = [var.security_group_ids]
}
run "unauthorized_node_version" {
  command = plan
  module { source = "../modules/aws/nodegroups" }
  variables { kubernetes_version = "1.98" }
  expect_failures = [var.kubernetes_version]
}
run "missing_disk_configuration" {
  command = plan
  module { source = "../modules/aws/nodegroups" }
  variables { root_volumes = {} }
  expect_failures = [var.root_volumes]
}
