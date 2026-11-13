# IAM S3 Backend Foundation (local, not connected, never applied)

Independent authority for the workspace S3 backend roles of
`aws/dev/iam/modules/s3-backend-access`. Its own State, approval and operator; the
workspace roles never create or change it. It creates:

- four per-operation permission boundaries
  `/adp/s3-backend/boundary/adp-s3-backend-<operation>-boundary`
  (`inspect`, `bootstrap`, `state-read`, `state-write`);
- the control role `/adp/control/adp-s3-backend-control`, which applies the
  workspace-role Terraform;
- as an OUTPUT only, the identity-side STS document `adp-agent-dev` will need
  after AdministratorAccess is removed (`agent_identity_policy`). Nothing is
  attached to the user; AdministratorAccess stays until a separate approval.

No EKS roles, no buckets, no users, no access keys.

## Boundaries (ceilings bound to the role's own tags)

One boundary per operation serves every workspace. Each Allow is limited to
`arn:aws:s3:::${aws:PrincipalTag/Bucket}` and, for State roles, to
`…/states/${aws:PrincipalTag/Team}/aws/<env>/${aws:PrincipalTag/Instance}/terraform.tfstate`
and its `.tflock`. `Bucket` is a role tag written once at creation (never a session
tag); `Team`/`Instance` are session tags that the role trust forces to the role's
own values. A role without these tags resolves nothing (fail closed). A Deny
limits every S3 action to the central workspace-bucket name pattern
(`<s3 prefix><region code>*<env code>??`), plus no bucket deletion or object
versions. The lock may only be created with `s3:if-none-match = *`. Every
session without `aws:SourceIdentity` is denied (`RequireSourceIdentity`), even
if a role had a weaker trust. The exact inline policy of each role is the
second, literal layer.

## Control role `adp-s3-backend-control`

Trust: only `adp-agent-dev`, session tag `Operation=s3-backend-control`,
SourceIdentity required, no transitive tags, session `adp-s3-backend-control*`.

| Allowed | Scope / condition |
|---|---|
| GetRole, GetRolePolicy, List*RolePolicies, ListRoleTags, ListInstanceProfilesForRole | `role/adp/s3-backend/*` |
| GetPolicy, GetPolicyVersion | the boundaries |
| CreateRole | `role/adp/s3-backend/<op>/*-s3backend-<op>`, exact boundary of `<op>`, tags ManagedBy=Terraform, Ownership=s3-backend-access, Operation=`<op>`, Team `D???`/`P???`, Instance `eks-??`, Bucket with the workspace-bucket shape, only reviewed tag keys |
| PutRolePermissionsBoundary | same roles, exact boundary of `<op>` |
| PutRolePolicy, TagRole | same roles, reviewed tag keys |

Denied: retagging Team/Instance/Bucket/Operation of an existing role; UntagRole;
UpdateAssumeRolePolicy and UpdateRole (trust/session changes go through this
foundation's approval); DeleteRole/DeleteRolePolicy/boundary removal; managed
policies, policy creation/versions; users, keys, PassRole; any IAM resource outside
`role/adp/s3-backend/*` and the boundaries (so never itself, `/adp/executor/`
Python roles, EKS or GitHub OIDC roles); S3/EC2/EKS/KMS data plane and role
chaining.

Known limits (activation blockers to verify in AWS, not solved offline; the
offline validator prints the residual explicitly):
- IAM cannot bind the `Bucket` tag to the role name: a compromised control can
  create `<bucketA>-s3backend-<op>` tagged `Bucket=<bucketB>`, reaching bucket B
  within the boundary. Candidate mitigation to test in AWS: Resource
  `role/adp/s3-backend/<op>/${aws:RequestTag/Bucket}-s3backend-<op>`; otherwise
  move CreateRole to the approved operator pipeline (no CreateRole in control),
  plus IAM Access Analyzer and an agent preflight (GetRole + digest of trust,
  tags and boundary) before every AssumeRole.
- CreateRole accepts the trust JSON as written: the control cannot be prevented by
  IAM from creating a role with a different trust. Mitigation: only the reviewed
  Terraform artifact runs as control, under approval; the boundary keeps any such
  role inside its own tagged bucket.
- Whether tagging at CreateRole is evaluated as TagRole, and the behaviour of
  `aws:ResourceTag` in that case, must be tested before relying on
  `NeverRetagIdentity`.
- `sts:TransitiveTagKeys` and SourceIdentity propagation must be tested with a
  real AssumeRole.

## Administrative backend (design only; NOT created)

Holds the bootstrap/IAM States, never EKS States and never inside a workspace
bucket:

| State key (relative) | Content |
|---|---|
| `s3-backend-foundation/<env>/terraform.tfstate` | this module |
| `s3-backend-access/<TEAM>/<eks-NN>/terraform.tfstate` | four roles of one workspace |
| `s3-backend-bucket/<TEAM>/<eks-NN>/terraform.tfstate` | bucket bootstrap of one workspace |

Requirements: dedicated bucket outside the workspace naming pattern (its name
must not match `<s3 prefix><region><team><env><NN>`), same account, versioning
enabled, SSE (S3 or reviewed KMS key), Block Public Access, BucketOwnerEnforced,
TLS-only bucket policy, access limited to the control role and the approved
operator; lifecycle that keeps noncurrent versions (recommended ≥ 90 days);
optional replication/backup to a second location.

Locking: S3 native lockfile (`use_lockfile = true`, Terraform ≥ 1.10); one
`.tflock` per State key; no DynamoDB. A stale lock is removed only with
`terraform force-unlock <ID>` after confirming that no process holds it, with
approval, and recorded. Never run two applies on the same key.

Partial backend configuration (portable placeholders, supplied at `init`):

```hcl
bucket       = "<ADMIN_BACKEND_BUCKET>"
key          = "s3-backend-access/<TEAM>/<eks-NN>/terraform.tfstate"
region       = "<REGION>"
encrypt      = true
use_lockfile = true
```

Initial bootstrap (chicken-and-egg): the administrative bucket cannot hold its
own creation State. Create it once, with approval, from a minimal root whose
State stays local in private operator custody (0600, encrypted backup), or create
it out of band and record it; then init every other root against it. Never use
temporary local State for the other roots and never the bucket being created.

Recovery: (1) stop all writers; (2) inspect the current object, its versions and
the `.tflock`; (3) restore the last good noncurrent version of the State object
(copy version over current) with approval; (4) `terraform plan` read-only to
compare against real resources; (5) reconcile, never blindly recreate or import.
Loss of the administrative bucket: recreate it from its private root, restore the
States from the backup, then verify each root with a read-only plan.

The existing bucket `s3ue1p001dev01` is not adopted, imported or modified here;
it stays as is until its configuration and State custody are reviewed.

## Offline validation

Validated together with `s3-backend-access` by
`tools/terraform/validate-s3-backend-access.py` (mocked provider, no AWS).
