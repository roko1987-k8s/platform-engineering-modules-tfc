# security-groups

Creates no security group. EKS creates and manages the cluster security group and attaches it to the control-plane ENIs and to the managed nodes (launch templates set no SG). This module receives its ID (`aws_eks_cluster.vpc_config[0].cluster_security_group_id`) and adds only approved standalone rules on it. Objects contain no CIDR input. Empty rules create no resources.

Rules managed by EKS on the cluster security group (not owned or revoked here): ingress of all traffic from the cluster security group itself, and egress of all traffic to 0.0.0.0/0. They cover node→API TCP443, control plane→kubelet TCP10250, DNS TCP/UDP53 to CoreDNS and node↔node traffic inside the VPC, and egress through the NAT Gateway to ECR, S3, STS and EKS.

A rule is an approved directed initiating flow with relation, source, destination, tcp/udp, from_port/to_port and approval_reference. The standard catalogue is unchanged: 110 System→User, 111 User→System, 112 User→User, eks-api, eks-kubelet, dns and dependency. Because system, user and control_plane share the cluster security group, approved flows between them are already allowed by the EKS-managed self rule: they are reported in `covered_by_eks` and create no duplicate resource. Flows to external destinations (reviewed endpoint SGs in the same VPC, e.g. VPC interface endpoints) create an explicit egress rule on the cluster SG, kept in Terraform for a later, separately approved egress restriction; their inbound rules remain the endpoint owner's responsibility. Duplicate/overlapping source/destination/protocol ranges are rejected, as are Any, DENY relationships and wildcard protocol -1.

500/501 describe implicit denial of unmatched ingress from outside the cluster security group. 502 (custom-SG egress denial) is not applied while the EKS-managed egress allows all; restricting it requires a separate approval. Kubernetes NetworkPolicy isolation is not claimed. AmazonProvidedDNS has AWS SG filtering limitations; these rules do not replace DNS Firewall.

## Inputs

`cluster_security_group_id`, `vpc_id`, `tags`, `rules`, `external_destinations`. See variables.tf for exact types, validations and optional defaults.

## Outputs

`cluster_security_group_id`, `approved_rules`, `covered_by_eks`, `terraform_managed_rules`, `eks_managed_rules`, `implicit_denials`.

Terraform >=1.9,<2; provider AWS pinned to 6.20.0. See ../../../README.md for validation and approval boundaries.
