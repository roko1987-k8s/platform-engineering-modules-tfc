# Reference only — blocked DEV composition

Read ../../../README.md and each module's README before use. This root demonstrates the dependency graph, not an activated workflow. Required variables deliberately have no environment defaults; do not copy synthetic test fixtures into a deployment.

`catalog_path` points to the sole authorized aws/dev/eks.yaml. Select its allowed version, region and role profiles; supply desired counts within each role's bounds. The reviewed Git commit and exact SHA-256 digest are required audit inputs; checkout provenance is the responsibility of the trusted caller. Approved network_option_id must map to the exact VPC/cluster_subnet_ids/node_subnet_ids. Today the catalogue remains pending with no network options, so this composition cannot be enabled successfully.

All modules use counts gated by enabled=false. Even with enabled=true, generation, provisioning, technical compatibility and AWS-managed cluster-SG behavior require explicit approvals. IAM/SG/cluster/node resources depend on the approval gate. No tfvars with environment values is committed. Mandatory inputs are fully listed in variables.tf; root_volumes and AMI release_version are independent pending technical decisions, not extra authorized catalogue options.

There is no backend, AWS credential input, Backstage request action, publication or Terraform execution bridge. Initialization/validate and mocked test instructions are in ../../README.md. Do not run real plan/apply. No observability integration is activated.
