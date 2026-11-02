mock_provider "aws" {
  mock_data "aws_partition" { defaults = { partition = "aws" } }
  mock_data "aws_region" { defaults = { region = "test-region-1" } }
  mock_data "aws_vpc" { defaults = { id = "vpc-00000001", enable_dns_support = true, enable_dns_hostnames = true } }
  mock_data "aws_subnet" { defaults = { vpc_id = "vpc-00000001", map_public_ip_on_launch = false } }
  mock_resource "aws_launch_template" { defaults = { latest_version = 1 } }
}
variables {
  name = "synthetic"
  tags = {}
}
run "separate_roles" {
  command = plan
  module { source = "../modules/aws/iam" }

  assert {
    condition     = length(aws_iam_role.nodes) == 2
    error_message = "System and User roles must remain separate."
  }
  assert {
    condition     = length(aws_iam_role.pod_identity) == 0
    error_message = "No add-on roles created without explicit policies."
  }
  assert {
    condition     = length(aws_iam_role_policy_attachment.nodes) == 4
    error_message = "Only worker and registry policies on node roles."
  }

}

run "admin_policy_denied" {
  command = plan
  module { source = "../modules/aws/iam" }
  variables {
    pod_identity_roles = { "bad" : { "policy_json" : "{\"Statement\": [{\"Effect\": \"Allow\", \"Action\": \"*\", \"Resource\": \"*\"}]}" } }
  }
  expect_failures = [var.pod_identity_roles]

}
