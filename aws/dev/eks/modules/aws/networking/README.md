# networking

Creates the EKS VPC and its private subnets from CIDRs assigned by Cloud
Infrastructure / Networking. It never invents, defaults or derives a segment:
without the `networking` input the composition keeps zero instances.

## Input `networking` (single variable)

| Field | Meaning |
|---|---|
| `vpc_cidr` | Canonical IPv4 CIDR, /16–/28, inside RFC 1918 (10/8, 172.16/12, 192.168/16). |
| `cluster_subnet_cidrs` | 2–6 subnets for the EKS control-plane ENIs. |
| `node_subnet_cidrs` | 2–6 subnets for the managed node groups. |
| `approval_reference` | Networking ticket/change ID that approved these CIDRs. Tagged on the VPC. |
| `connectivity` | Optional. Attested by Networking after the VPC exists: `routing_reviewed`, `private_api_reachable`, `dns_reviewed`, `registry_sts_eks_reachable`. |

Validations: every subnet is canonical, no smaller than /28, inside `vpc_cidr`,
and no two subnets repeat or overlap (cluster and node sets are separate subnets).

Other inputs: `name` and `subnet_names` from the central naming module
(`../../naming`), `region` from the central catalog `aws/dev/eks.yaml`, and `tags`.

## Behaviour

- VPC with DNS support and DNS hostnames enabled (required by private EKS endpoints).
- Subnets with `map_public_ip_on_launch = false`.
- No security group is created or managed here (including the VPC default SG);
  EKS security groups belong to the `security-groups` module.
- Availability zones: the inherited provider must be in the catalog region; the
  module reads the region's available, opt-in-free zones, sorts them, uses as many
  as the largest subnet set needs, and assigns subnet `i` to zone `i mod count`.
  At least two zones are required, so each set always spans two or more zones.
- Names: VPC `names.vpc`, subnets `<names.vpc>-cluster-NN` / `<names.vpc>-node-NN`.
  Tags carry `SubnetRole` and the identity tags supplied by the composition.

## Two-stage gate (no circular dependency)

Connectivity can only be reviewed once the VPC exists. The approved CIDRs and
approval reference are enough to create the VPC and subnets; `connectivity_ready`
is reported as an output and the composition creates IAM, security groups, EKS,
add-ons and node groups only when it is true.

## Pending decisions (not implemented)

No Internet Gateway, NAT Gateway, VPC endpoint, custom route table or NACL is
created. Subnets use the VPC main route table (local route only), so nodes cannot
yet reach ECR, S3, STS or the EKS API. An approved egress design is required
before `registry_sts_eks_reachable` can be attested: NAT (with IGW/public subnets)
or interface/gateway endpoints (ecr.api, ecr.dkr, s3, sts, eks, ec2, logs), or
transit routing. Also pending: internal load-balancer subnet tags, VPC flow logs,
free-IP sizing per node group, and pinning zones by AZ ID if the sorted-name
placement is not acceptable.

## Outputs

`vpc_id`, `vpc_cidr`, `cluster_subnet_ids`, `node_subnet_ids` (same order as the
CIDRs), `availability_zones`, `subnets`, `connectivity`, `connectivity_ready`.

Terraform >=1.9,<2; provider AWS pinned to 6.20.0. See ../../../README.md for validation and approval boundaries.
