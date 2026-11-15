# Terraform executor roles (Vault + STS)

Execution identities for the Terraform Infrastructure Agent. Paths are relative
to the repository root.

- Three roles, exactly `plan`, `apply` and `destroy`, with approved names
  (`roles`). They are shared by every team; there are no per-team roles, IAM
  users or access keys in this module.
- Trust: only `vault_principal_arn` may call `sts:AssumeRole` (the IAM principal
  of the Vault AWS secrets engine). Sessions last at most one hour.
- Per-team isolation: each Vault role (one per team and operation, Vault-side
  configuration) passes a session policy limited to that team's backend bucket,
  its state key and resources tagged with its `Team`. The effective permissions
  are the intersection of this role and that session policy. The agent's
  `app/execution/vault_contract.py` renders those Vault role payloads.
- State: the same actions as `aws/dev/iam/modules/github-oidc/state.json` on the
  approved per-team buckets (`state_buckets`), keys
  `states/aws/<environment>/<deployment>/terraform.tfstate` and their lock.
- Provisioning: `networking-read.json` (plan), plus `networking-apply.json`
  (apply) or `networking-destroy.json` (destroy), pinned to the catalog region.
  Apply has no delete actions and destroy has no create actions. Attached only
  for phases listed in `provisioning_phases` (empty by default = blocked).
- EKS cluster permissions (EKS, IAM `CreateRole`/`PassRole`, KMS, CloudWatch Logs,
  launch templates, security groups) are **not** defined yet: they require their
  own review before `EKS_CLUSTER` can run.

The action lists are the minimum for the networking module resources and must be
confirmed against CloudTrail on the first real plan. Vault itself needs an AWS
identity allowed to assume these roles; in the local lab that is a pending
architecture decision (a dedicated principal with only `sts:AssumeRole` on these
three roles, or workload identity federation when Vault is reachable by AWS).
