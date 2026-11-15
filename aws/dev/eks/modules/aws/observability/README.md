# observability

Disabled-by-default integration contract only. When explicitly enabled with approval and selected metric names it exposes the cluster/log-group/ContainerInsights metric contract via terraform_data, not an AWS resource. It does not install collectors, create dashboards/alarms, run Kubernetes commands or assume that Container Insights data exists. The EKS module owns control-plane logs; this module never duplicates them. Actual metric collection and integrations remain a separately approved component. Empty/disabled input creates no contract instance. Outputs are reusable by an eventual approved observability composition.

## Inputs

`enabled`, `cluster_name`, `log_group_name`, `approval_reference`, `metrics`. See variables.tf for exact types, validations and optional defaults. Required inputs have no guessed environment values.

## Outputs

`integration`.

Terraform >=1.9,<2; provider AWS pinned to 6.20.0. See ../../../README.md for validation and approval boundaries.
