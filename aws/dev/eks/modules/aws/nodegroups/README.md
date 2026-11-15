# nodegroups

Creates exactly System and User managed node groups and one launch template per role. The catalogue resolves each role's S/M to an EC2 type and its capacity/range constraints; selections never supply an instance type. Desired count is explicit. Maximum counts are summed against the single catalogue aggregate limit. Both node groups use separate IAM roles from the IAM module and the EKS cluster security group.

AMI ownership is solely the managed node group: AL2023_x86_64_STANDARD, cluster Kubernetes version, and an explicitly reviewed EKS AMI release_version. The launch template intentionally has NO image_id, instance_type, user_data, subnet or IAM instance profile. EKS supplies the matching managed AL2023 bootstrap/nodeadm data; do not add custom-AMI bootstrap fields without changing this contract. Instance selection occurs only on the node group.

Launch templates set no security group or network interface, so EKS attaches its cluster security group to every node (a launch-template SG would replace it). IMDSv2 is required with hop limit 1; pods must use approved workload identity instead of node IMDS credentials. Encrypted gp3 root volume size and customer KMS key are explicit separate inputs, without laboratory defaults. The AL2023 root device is /dev/xvda; minimum size must be checked against the chosen AMI release. The key policy must permit the EC2 Auto Scaling service-linked role.

Labels differentiate roles, but are not authorization. Optional taints enforce Kubernetes syntax, EKS effects and unique key/effect pairs. No default taint isolates System automatically: workload tolerations and scheduling policy remain an approval decision. Updates recycle nodes through a pinned numeric launch-template version; max_unavailable=1 may disrupt a one-node group and must be reviewed with PDBs and subnet/IP capacity. Desired count is NOT ignored in lifecycle (no external autoscaler ownership is assumed). Changing launch-template identity, removing a template, unsupported AMI/version transitions and EC2 capacity may require replacement or fail in AWS; mocks do not certify those transitions.

## Inputs

`cluster_name`, `kubernetes_version`, `catalog`, `subnet_ids`, `node_role_arns`, `cluster_security_group_id`, `tags`, `selections`, `root_volumes`. See variables.tf for exact types, validations and optional defaults. Required inputs have no guessed environment values.

## Outputs

`groups`.

Terraform >=1.9,<2; provider AWS pinned to 6.20.0. See ../../../README.md for validation and approval boundaries.
