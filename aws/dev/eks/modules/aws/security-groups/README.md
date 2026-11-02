# security-groups

Owns three custom SGs (control_plane, system, user) and only standalone ingress/egress rule resources. SG creation removes EC2's automatically added allow-all egress; no inline permissions or allow-all CIDRs/protocols are authored. Objects contain no CIDR input. Empty rules create no communications. External destinations must be explicitly reviewed SGs in the same VPC, e.g. existing VPC interface endpoints; their inbound rules remain the endpoint owner's responsibility.

A rule is an approved directed initiating flow with relation, source, destination, tcp/udp, from_port/to_port and approval_reference. For internal destinations the source egress and destination ingress must both permit that initiating flow. This is NOT an additional symmetric return rule: SGs are stateful. Reverse initiating flows need a separately justified rule. SGs are created first, references are resolved afterward, avoiding graph cycles. Duplicate/overlapping source/destination/protocol ranges are rejected, as are Any, DENY relationships and wildcard protocol -1.

110 System→User, 111 User→System and 112 User→User have no default port and therefore no default rule. 500/501 are descriptions of implicit unmatched ingress denial. 502 is provisional unmatched custom-SG egress denial, not a standalone AWS DENY. No absolute packet ordering or priority is implied by these IDs. Existing unrelated SGs or workload networking policies can still affect traffic; the design does not claim Kubernetes NetworkPolicy isolation.

Technical flow constructors identify TCP443 node→API, TCP10250 control plane→kubelet, and TCP/UDP53 DNS, but still require a supplied explicit rule and approval. Actual DNS location (CoreDNS/node-local/VPC resolver), pod-to-pod ports, registry/S3/STS/EKS endpoints and other egress must be reviewed by Networking. AmazonProvidedDNS has AWS SG filtering limitations; these SGs do not replace DNS Firewall. Default EKS-managed control-plane SG rules are outside this module and documented in eks/README.md.

## Inputs

`name`, `vpc_id`, `tags`, `rules`, `external_destinations`. See variables.tf for exact types, validations and optional defaults. Required inputs have no guessed environment values.

## Outputs

`security_group_ids`, `approved_rules`, `implicit_denials`.

Terraform >=1.9,<2; provider AWS pinned to 6.20.0. See ../../../README.md for validation and approval boundaries.
