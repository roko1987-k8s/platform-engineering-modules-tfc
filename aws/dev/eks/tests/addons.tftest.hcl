mock_provider "aws" {
  mock_data "aws_partition" { defaults = { partition = "aws" } }
  mock_data "aws_region" { defaults = { region = "test-region-1" } }
  mock_data "aws_vpc" { defaults = { id = "vpc-00000001", enable_dns_support = true, enable_dns_hostnames = true } }
  mock_data "aws_subnet" { defaults = { vpc_id = "vpc-00000001", map_public_ip_on_launch = false } }
  mock_resource "aws_launch_template" { defaults = { latest_version = 1 } }
}
variables {
  cluster_name = "synthetic"
  tags         = {}
}
run "no_addons_by_default" {
  command = plan
  module { source = "../modules/aws/addons" }

  assert {
    condition     = length(aws_eks_addon.managed) == 0
    error_message = "No unapproved add-on versions are selected."
  }

}

run "unapproved_version" {
  command = plan
  module { source = "../modules/aws/addons" }
  variables {
    addons = { "coredns" : { "version" : "latest", "ownership_approved" : true } }
  }
  expect_failures = [var.addons]

}

run "ownership_denied" {
  command = plan
  module { source = "../modules/aws/addons" }
  variables {
    addons = { "coredns" : { "version" : "v1.99.0-eksbuild.1", "ownership_approved" : false } }
  }
  expect_failures = [var.addons]

}

run "cni_without_workload_role" {
  command = plan
  module { source = "../modules/aws/addons" }
  variables {
    addons = { "vpc-cni" : { "version" : "v1.99.0-eksbuild.1", "ownership_approved" : true } }
  }
  expect_failures = [var.addons]

}

run "approved_synthetic_addon" {
  command = plan
  module { source = "../modules/aws/addons" }
  variables {
    addons = { "coredns" : { "version" : "v1.99.0-eksbuild.1", "ownership_approved" : true } }
  }
  assert {
    condition     = aws_eks_addon.managed["coredns"].resolve_conflicts_on_create == "NONE"
    error_message = "Never steal existing ownership."
  }

}

run "pod_identity_requires_agent" {
  command = plan
  module { source = "../modules/aws/addons" }
  variables {
    addons = { "vpc-cni" = { version = "v1.99.0-eksbuild.1", ownership_approved = true, pod_identity_associations = { "aws-node" = "arn:aws:iam::000000000000:role/synthetic-cni" } } }
  }
  expect_failures = [var.addons]
}
run "identity_strategy_conflict" {
  command = plan
  module { source = "../modules/aws/addons" }
  variables {
    addons = { "vpc-cni" = { version = "v1.99.0-eksbuild.1", ownership_approved = true, service_account_role_arn = "arn:aws:iam::000000000000:role/synthetic-cni", pod_identity_associations = { "aws-node" = "arn:aws:iam::000000000000:role/synthetic-cni" } } }
  }
  expect_failures = [var.addons]
}
run "pod_identity_foundation" {
  command = plan
  module { source = "../modules/aws/addons" }
  variables {
    addons = {
      "eks-pod-identity-agent" = { version = "v1.99.0-eksbuild.1", ownership_approved = true }
      "vpc-cni"                = { version = "v1.99.0-eksbuild.1", ownership_approved = true, pod_identity_associations = { "aws-node" = "arn:aws:iam::000000000000:role/synthetic-cni" } }
    }
  }
  assert {
    condition     = length(aws_eks_addon.identity_agent) == 1 && length(aws_eks_addon.managed) == 1
    error_message = "Identity agent has unique ownership and precedes CNI."
  }
}
