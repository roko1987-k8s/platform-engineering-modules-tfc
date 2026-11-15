# iam

Creates an EKS control-plane role with AmazonEKSClusterPolicy and two distinct EC2 node roles. Each node gets only AmazonEKSWorkerNodePolicy and AmazonEC2ContainerRegistryPullOnly, not CNI permissions and never AdministratorAccess. These AWS policies have AWS-managed scopes and can change; review their current AWS documents before deployment. No static keys, users or service-account credentials are generated. Cluster/node roles trust only the corresponding AWS service.

Optional explicitly supplied resource-scoped policies create workload roles trusting pods.eks.amazonaws.com with sts:AssumeRole and sts:TagSession. Wildcard actions/global resources are rejected; this is an additional guard, not an IAM privilege-escalation analyzer. Every supplied policy still requires security approval. Empty input creates no workload role. Add-on association is owned by addons; IAM owns only roles/policies. The caller must select either approved Pod Identity or an externally managed IRSA role for an add-on. No OIDC provider, IRSA trust or arbitrary administrative grant is guessed. Output policy attachments are explicit dependencies so clusters/nodes cannot race role attachment.

## Inputs

`name`, `tags`, `pod_identity_roles`. See variables.tf for exact types, validations and optional defaults. Required inputs have no guessed environment values.

## Outputs

`cluster_role_arn`, `node_role_arns`, `pod_identity_role_arns`.

Terraform >=1.9,<2; provider AWS pinned to 6.20.0. See ../../../README.md for validation and approval boundaries.
