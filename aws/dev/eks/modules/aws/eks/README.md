# eks

Creates only the cluster and its CloudWatch control-plane log group. IAM, networking, security group rules and add-ons belong to other modules; no custom SG is attached. Accepts the decoded authoritative catalogue plus version/region selections; never contains a second list of permitted AWS versions, regions or instance types.

The API endpoint is private-only, authentication is API-based, implicit creator admin is disabled, deletion protection is on. All five control-plane log categories are enabled with an explicit finite retention. An existing regional customer KMS key is required for secrets and logs; its policy must authorize EKS and the regional CloudWatch Logs service separately. No key or administrator access entry is created. A separately reviewed access-entry workflow will be required for human/workload administration.

AWS creates and manages the cluster security group (self-referencing all-traffic ingress, all-traffic egress) and attaches it to the control-plane ENIs and to the managed nodes. This module reports its ID (`aws_managed_cluster_security_group_id`) and does not own or revoke its rules; additional approved rules are added by the security-groups module. No local-exec, imperative revocation or resource adoption/import is hidden here.

AWS availability of version 1.36, regional support, quotas, KMS grants and endpoint reachability cannot be established by mock plans. The approved YAML is an organizational input, not proof of AWS API availability. Upgrades are explicit; downgrades are not supported by EKS. Deletion requires a later approved change disabling deletion protection.

## Inputs

`name`, `catalog`, `kubernetes_version`, `region`, `role_arn`, `subnet_ids`, `kms_key_arn`, `log_retention_days`, `tags`. See variables.tf for exact types, validations and optional defaults. Required inputs have no guessed environment values.

## Outputs

`name`, `arn`, `endpoint`, `certificate_authority_data`, `oidc_issuer`, `aws_managed_cluster_security_group_id`.

Terraform >=1.9,<2; provider AWS pinned to 6.20.0. See ../../../README.md for validation and approval boundaries.
