# Pure reusable naming

Computes `<resource><regionCode><teamId><environment><sequence>` from a trusted policy and explicit context. No provider, resource, data source, AWS call or stateful sequence allocator. Region/environment keys require explicit mappings; there is no abbreviation fallback. The team input is canonical uppercase (letter + three digits) and is rendered lowercase without changing its identity. There is no D001-specific branch.

`../../naming/aws.json` relative to this module contains the approved AWS naming policy; consumers load it with jsondecode(file(...)). Its region map is naming metadata, not another infrastructure-region allowlist. Infrastructure options continue to come from aws/dev/eks.yaml.

The approved us-east-1 code is ue1, not use1. Existing environment codes dev/cert/prod are retained. Prefixes eks/vpc/infra/user follow the approved convention. Sequence is an explicit positive integer formatted to at least two digits: 1 -> 01, 10 -> 10, 100 -> 100. It is never silently truncated; uniqueness/allocation of a sequence is a separate caller responsibility. This module does not claim a name is reserved or collision-free across workspaces.

Inputs: policy, region, environment, team_id, sequence. Output: names map. Rejects unknown region/environment, malformed team/sequence, duplicate naming codes, malformed policy and names exceeding the existing EKS module's limit. Naming does not authenticate users or grant permissions.

The EKS template consumes names.eks. names.vpc/infra/user are review outputs only; the existing Networking module neither creates nor renames VPCs/subnets. Security Groups keep their existing naming and rules unchanged.

Operational validation is documented in the repository root README. Temporary tests run outside the published repository. No runtime dependency is added to Backstage or either agent.
