# IAM S3 Backend Access — one bucket per workspace (local, not connected)

One module invocation owns the four backend IAM roles of ONE authorized workspace
(`eks-NN`) and its own bucket, in one AWS account/region/environment. It creates
no bucket, boundary, control identity, EKS resource or binding record. Do not put
this module in an EKS state. A new workspace is a new invocation (and a new State),
never an edit of another workspace's roles.

## Contract

Terraform >= 1.10, < 2; AWS provider ~> 6.0 (offline checks use cached 6.20.0).
The relative naming dependency is the existing pure `aws/dev/eks/modules/naming`
and its central `naming/aws.json`; distribute this module with that repository
layout. No remote module downloads are needed for naming.

| Input | Source required before operational integration |
|---|---|
| `authorized_team_id` | Backend-verified identity and workspace authorization, never browser/LLM input |
| `workspace` | Literal GP01 inputs of ONE workspace: id, team_id, application_code, environment, region, sequence; source.repository, immutable 40-character commit, exact source.path |
| `backend` | account_id, region, environment, assignment_revision (64-character digest of the server-side assignment), approval_reference. The bucket is derived, never supplied |
| `foundation` | The IAM user `adp-agent-dev` (only approved source identity), the four per-operation boundary ARNs of `s3-backend-foundation`, revision and approval_reference |

Outputs: `resolved` (bucket, State/lock keys, role names/paths, provenance),
`role_arns`, `policies` and `trust_policies` indexed by operation, and
`foundation_requirements` (expected boundary ARNs). None contains credentials.
Names and approval strings alone do not authenticate identity, attest a commit,
prove AWS existence or ownership, or verify boundary contents.

## Naming (paths relative to the repository root)

Bucket = `names.s3` with the INSTANCE sequence. Synthetic examples:

| Workspace | Bucket | State |
|---|---|---|
| P001 / eks-01 | `s3ue1p001dev01` | `states/P001/aws/dev/eks-01/terraform.tfstate` |
| P001 / eks-02 | `s3ue1p001dev02` | `states/P001/aws/dev/eks-02/terraform.tfstate` |
| D001 / eks-01 | `s3ue1d001dev01` | `states/D001/aws/dev/eks-01/terraform.tfstate` |

Lock = State key + `.tflock` (S3 native locking, `use_lockfile = true`).
Roles = `<bucket>-s3backend-<operation>` under `/adp/s3-backend/<operation>/`,
operation in `inspect`, `bootstrap`, `state-read`, `state-write` (≤ 64 chars,
never truncated). Role tags: ManagedBy, Ownership, Team, Instance (`eks-NN`),
Bucket, Environment, Operation, ApplicationCode.

## Permissions (inline policy, exact ARNs, no Allow wildcard)

| Role | Allowed | Scope |
|---|---|---|
| inspect | GetBucketLocation, GetBucketOwnershipControls, GetBucketPolicy, GetBucketPublicAccessBlock, GetBucketTagging, GetBucketVersioning, GetEncryptionConfiguration | own bucket ARN; no objects |
| bootstrap | CreateBucket, reviewed Get*/ListBucket metadata, PutBucketOwnershipControls/Policy/PublicAccessBlock/Tagging/Versioning, PutEncryptionConfiguration | own bucket ARN, `aws:RequestedRegion` = approved region; no objects |
| state-read | GetBucketLocation; ListBucket with `s3:prefix` = State/lock key; GetObject State; Get/DeleteObject lock; PutObject lock only with `s3:if-none-match = *` (create, never overwrite) | own bucket, own State and own `.tflock` |
| state-write | state-read + PutObject State | same; never DeleteObject on the State |

Every role denies `s3:*` outside its own resources (`NotResource`), bucket
deletion, object versions/ACLs and `iam:*`, `sts:AssumeRole*`, `ec2:*`, `eks:*`,
`kms:*` (no role chaining; SSE-S3 assumed). State roles also deny every bucket
configuration mutation. state-read can never write the State; it can create
(conditional write) and release its own `.tflock`, which Terraform requires for
`plan` with `use_lockfile = true`. A holder of state-read could still delete a
lock held by another session of the same workspace (S3 has no conditional
delete in IAM): the agent must serialize operations per workspace. Isolation therefore holds between workspaces of the same
team: P001/eks-01 roles cannot touch `s3ue1p001dev02`. Provider refresh behaviour
and real AWS evaluation remain unverified offline.

## Trust (STS AssumeRole)

Exactly one principal: the IAM user `adp-agent-dev` of the approved account (never
root, wildcard, roles, STS sessions, GitHub OIDC or Vault identities). Following
IAM semantics (validated with IAM Access Analyzer): `sts:AssumeRole` +
`sts:SetSourceIdentity` require a non-null SourceIdentity (the verified employeeId)
and the session name; `sts:TagSession` admits only the tags Team, Instance
(`eks-NN`) and Operation with those exact values and no other keys; explicit Deny
statements reject an AssumeRole whose tags are missing or different, and any
transitive tag keys. Session name
`adp-<TEAM>-<eks-NN>-<operation>*` (the agent's helper builds
`adp-<label>-<operation>` with label `<TEAM>-<eks-NN>`). Tags/SourceIdentity are audit context asserted
by the trusted technical principal, not proof of Keycloak identity. The principal
needs matching identity-side STS permissions (`s3-backend-foundation` output
`agent_identity_policy`, not attached). Maximum session duration is one hour.

## Foundation and control (separate module and State)

`aws/dev/iam/modules/s3-backend-foundation` owns the four per-operation boundaries
(ceilings bound to each role's own Bucket/Team/Instance tags) and the control role
`adp-s3-backend-control`. This module never creates or changes its own authority;
it only checks the ARNs. See that README for the control permissions, the
administrative backend and recovery.

## Ownership, persistence and recovery

Role paths `/adp/s3-backend/<operation>/`, tagged ManagedBy=Terraform /
Ownership=s3-backend-access. No import, no Python ownership (`iam_bootstrap.py`
roles under `/adp/executor/` remain untouched and are still used by the
Terraform Plan/Apply Golden Path). State per workspace in the administrative
backend (key `s3-backend-access/<TEAM>/<eks-NN>/terraform.tfstate`), never in a
workspace bucket. `prevent_destroy` guards every resource while configuration
exists. Never blindly recreate or import after an interruption: inspect the
persisted State/lock and real resources, reconcile under approval.

## Offline validation

```sh
python3 tools/terraform/validate-s3-backend-access.py \
  --terraform-bin "$TERRAFORM_BIN" \
  --provider-mirror "$LOCAL_PROVIDER_MIRROR" \
  --lockfile "$REVIEWED_PROVIDER_LOCK"
```

The tool copies sources into a disposable directory, generates synthetic fixtures,
uses only the filesystem mirror and readonly lock, hides AWS config/credentials,
and runs fmt, init (backend=false), validate and `terraform test` with a mocked
AWS provider (`command = plan`), plus an offline IAM evaluation of the generated
documents (cross-workspace and cross-team denial). No real plan, refresh, apply,
backend connection or cloud request is used. The offline evaluation is a
simplified model of IAM: it never replaces a later authorized check in AWS.

Activation requires separate authorization: approved Foundation/control and
administrative backend; reviewed boundaries; current GP01 inputs and bindings;
AWS policy evaluation in an isolated authorized environment; then agent
consumption behind an explicit route, without changing current GP02 credentials.
