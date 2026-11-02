mock_provider "aws" {
  mock_data "aws_partition" { defaults = { partition = "aws" } }
  mock_data "aws_region" { defaults = { region = "test-region-1" } }
  mock_data "aws_vpc" { defaults = { id = "vpc-00000001", enable_dns_support = true, enable_dns_hostnames = true } }
  mock_data "aws_subnet" { defaults = { vpc_id = "vpc-00000001", map_public_ip_on_launch = false } }
  mock_resource "aws_launch_template" { defaults = { latest_version = 1 } }
}
variables {
  name   = "synthetic"
  vpc_id = "vpc-00000001"
  tags   = {}
}
run "implicit_deny_only" {
  command = plan
  module { source = "../modules/aws/security-groups" }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.approved) == 0 && length(aws_vpc_security_group_egress_rule.approved) == 0
    error_message = "No pending relationship may open traffic."
  }
  assert {
    condition     = length(aws_security_group.role) == 3
    error_message = "Separate control plane, System and User SG ownership."
  }

}

run "approved_specific_flow" {
  command = plan
  module { source = "../modules/aws/security-groups" }
  variables {
    rules = { "synthetic110" : { "relation" : "110", "source" : "system", "destination" : "user", "protocol" : "tcp", "from_port" : 8443, "to_port" : 8443, "approval_reference" : "SYNTHETIC-TEST-ONLY" } }
  }
  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.approved) == 1 && length(aws_vpc_security_group_egress_rule.approved) == 1
    error_message = "One initiator flow requires source egress and destination ingress, no return-flow rules."
  }

}

run "any_source" {
  command = plan
  module { source = "../modules/aws/security-groups" }
  variables {
    rules = { "synthetic" : { "relation" : "110", "source" : "Any", "destination" : "user", "protocol" : "tcp", "from_port" : 8443, "to_port" : 8443, "approval_reference" : "SYNTHETIC-TEST-ONLY" } }
  }
  expect_failures = [var.rules]

}

run "any_destination" {
  command = plan
  module { source = "../modules/aws/security-groups" }
  variables {
    rules = { "synthetic" : { "relation" : "110", "source" : "system", "destination" : "Any", "protocol" : "tcp", "from_port" : 8443, "to_port" : 8443, "approval_reference" : "SYNTHETIC-TEST-ONLY" } }
  }
  expect_failures = [var.rules]

}

run "all_protocols" {
  command = plan
  module { source = "../modules/aws/security-groups" }
  variables {
    rules = { "synthetic" : { "relation" : "110", "source" : "system", "destination" : "user", "protocol" : "-1", "from_port" : 8443, "to_port" : 8443, "approval_reference" : "SYNTHETIC-TEST-ONLY" } }
  }
  expect_failures = [var.rules]

}

run "deny_rule" {
  command = plan
  module { source = "../modules/aws/security-groups" }
  variables {
    rules = { "synthetic" : { "relation" : "500", "source" : "system", "destination" : "user", "protocol" : "tcp", "from_port" : 8443, "to_port" : 8443, "approval_reference" : "SYNTHETIC-TEST-ONLY" } }
  }
  expect_failures = [var.rules]

}

run "missing_approval" {
  command = plan
  module { source = "../modules/aws/security-groups" }
  variables {
    rules = { "synthetic" : { "relation" : "110", "source" : "system", "destination" : "user", "protocol" : "tcp", "from_port" : 8443, "to_port" : 8443, "approval_reference" : "" } }
  }
  expect_failures = [var.rules]

}

run "inverted_ports" {
  command = plan
  module { source = "../modules/aws/security-groups" }
  variables {
    rules = { "synthetic" : { "relation" : "110", "source" : "system", "destination" : "user", "protocol" : "tcp", "from_port" : 9000, "to_port" : 8000, "approval_reference" : "SYNTHETIC-TEST-ONLY" } }
  }
  expect_failures = [var.rules]

}

run "wrong_relationship" {
  command = plan
  module { source = "../modules/aws/security-groups" }
  variables {
    rules = { "synthetic" : { "relation" : "110", "source" : "system", "destination" : "system", "protocol" : "tcp", "from_port" : 8443, "to_port" : 8443, "approval_reference" : "SYNTHETIC-TEST-ONLY" } }
  }
  expect_failures = [var.rules]

}

run "unknown_protocol" {
  command = plan
  module { source = "../modules/aws/security-groups" }
  variables {
    rules = { "synthetic" : { "relation" : "110", "source" : "system", "destination" : "user", "protocol" : "icmp", "from_port" : 8443, "to_port" : 8443, "approval_reference" : "SYNTHETIC-TEST-ONLY" } }
  }
  expect_failures = [var.rules]

}

run "zero_port" {
  command = plan
  module { source = "../modules/aws/security-groups" }
  variables {
    rules = { "synthetic" : { "relation" : "110", "source" : "system", "destination" : "user", "protocol" : "tcp", "from_port" : 0, "to_port" : 8443, "approval_reference" : "SYNTHETIC-TEST-ONLY" } }
  }
  expect_failures = [var.rules]

}

run "wide_port" {
  command = plan
  module { source = "../modules/aws/security-groups" }
  variables {
    rules = { "synthetic" : { "relation" : "110", "source" : "system", "destination" : "user", "protocol" : "tcp", "from_port" : 8443, "to_port" : 65536, "approval_reference" : "SYNTHETIC-TEST-ONLY" } }
  }
  expect_failures = [var.rules]

}

run "duplicate_rule" {
  command = plan
  module { source = "../modules/aws/security-groups" }
  variables {
    rules = { "one" : { "relation" : "110", "source" : "system", "destination" : "user", "protocol" : "tcp", "from_port" : 8443, "to_port" : 8443, "approval_reference" : "SYNTHETIC-TEST-ONLY" }, "two" : { "relation" : "110", "source" : "system", "destination" : "user", "protocol" : "tcp", "from_port" : 8443, "to_port" : 8443, "approval_reference" : "SYNTHETIC-TEST-ONLY" } }
  }
  expect_failures = [var.rules]

}

run "overlapping_rule" {
  command = plan
  module { source = "../modules/aws/security-groups" }
  variables {
    rules = { "one" : { "relation" : "110", "source" : "system", "destination" : "user", "protocol" : "tcp", "from_port" : 8000, "to_port" : 8500, "approval_reference" : "SYNTHETIC-TEST-ONLY" }, "two" : { "relation" : "110", "source" : "system", "destination" : "user", "protocol" : "tcp", "from_port" : 8443, "to_port" : 8443, "approval_reference" : "SYNTHETIC-TEST-ONLY" } }
  }
  expect_failures = [var.rules]

}

run "cidr_destination_rejected" {
  command = plan
  module { source = "../modules/aws/security-groups" }
  variables {
    external_destinations = { "internet" : "0.0.0.0/0" }
  }
  expect_failures = [var.external_destinations]

}
