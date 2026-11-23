# security-groups

AWS translation of `network/rules.yaml` (repository root): the network rules of every cluster, defined once for all
clouds. This module maps its logical endpoints to AWS objects (`any` = 0.0.0.0/0, `lb` = `<names.sg>-ingress`,
`system`/`user` = own node groups, `control_plane` = EKS cluster group, `jump` = SSM jump host group) and creates
the instance's own security groups and every allowed flow as an explicit rule tagged `RuleId`: ingress half on the
destination, egress half only on sources with closed egress (`lb`, `jump`). Rules are never written here.

**One logical rule = one entry with all its ports** (`ports = ["80", "443"]`, ranges as `"N-M"`). AWS accepts a single
contiguous port range per security group rule, so the module expands each entry into one AWS rule per
source × destination × port range, all with the same `RuleId` (never a range like 80-443 that would open the ports in
between). Output `rules` shows the logical view.

| Group | Members |
|---|---|
| `<names.sg>-system` | System managed nodes (launch template) |
| `<names.sg>-user` | User managed nodes (launch template) |
| `<names.sg>-ingress` | Internal NLB of the Istio gateway, passed to the AWS Load Balancer Controller with `service.beta.kubernetes.io/aws-load-balancer-security-groups` and `manage-backend-security-group-rules: "false"` |
| EKS cluster security group | Created by EKS (unavoidable), control plane only; this module adds rules 100/101 on it |

Rules today (from `network/rules.yaml`):

| RuleId | Flow | Ports |
|---|---|---|
| 100 | control plane → System, User | TCP 443, 1025-65535 (kubelet, webhooks) |
| 101 | System, User → control plane | TCP 443 |
| 102 | SSM jump host → System, User | Not created: ports pending |
| 103 | any (`0.0.0.0/0`) → ingress | TCP 80, 443; the jump host also gets egress to the NLB on 80/443 |
| 104 | ingress → User | TCP 80, 443, 15021 (gateway pods, health check), ingress on User and egress on ingress |
| 110 / 111 / 112 / 113 | System→User / User→System / User→User / System→System | all (`-1`), as under the former EKS self rule |
| egress | System, User → `0.0.0.0/0` | all (NAT: ECR, S3, STS, EKS); 502 restriction not applied |
| 210 / 212 | any → System / User | Implicit: security groups deny whatever no rule allows |

Custom rules: `custom_rules` (from `reviewed_execution.custom_security_group_rules`), RuleId **150-199** only (between the
base allows and the 210/212 denials), all its ports in one entry (`ports`, `"N"` or `"N-M"`, no overlaps), TCP/UDP, known source (`system`, `user`, `lb`,
`control_plane` or a reviewed `external_sources` SG) and destination (`system`, `user`, `lb`), approval reference
required, no `-1`, no CIDR, no deny, no overlap. They are reserved for a future Golden Path.

Network ACLs are not used: System and User share the node subnets and a NACL cannot tell them apart.

## Inputs

`name`, `rules_catalog`, `cluster_name`, `cluster_security_group_id`, `vpc_id`, `jump_enabled`, `jump_security_group_id`, `tags`,
`custom_rules`, `external_sources`.

## Outputs

`security_group_ids`, `node_security_group_ids`, `ingress_security_group_id`, `cluster_security_group_id`, `rules`,
`implicit_denials`.

Terraform >=1.9,<2; provider AWS pinned to 6.20.0. See ../../../README.md for validation and approval boundaries.
