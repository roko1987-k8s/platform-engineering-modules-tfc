variables {
  cluster_name   = "synthetic"
  log_group_name = "/synthetic"
}
run "disabled_observability" {
  command = plan
  module { source = "../modules/aws/observability" }

  assert {
    condition     = output.integration == null && length(terraform_data.contract) == 0
    error_message = "No optional components by default."
  }

}

run "unapproved_observability" {
  command = plan
  module { source = "../modules/aws/observability" }
  variables {
    enabled = true
    metrics = ["synthetic_metric"]
  }
  expect_failures = [terraform_data.contract]

}
