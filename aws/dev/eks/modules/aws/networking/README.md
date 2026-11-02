# networking

Creates NO VPC, subnet, route, NAT or VPC endpoint. Looks up the supplied VPC/subnets using data sources, validates their formats/uniqueness, VPC membership, VPC DNS support/hostnames, two availability zones for each subnet set, and no automatic public IP allocation on node subnets. Data lookups require credentials only in a future approved live plan; tests mock them.

Networking must provide conformity=approved and a nonempty approval reference with explicit review of routing, private API reachability, DNS and registry/STS/EKS connectivity. Those attestations are not live network probes. Provide approved VPC ID, cluster and node subnet IDs, AZ placement, free-IP sizing, routes, DNS, endpoint SG ownership, S3/ECR/STS/EKS reachability and any other required egress. Cluster subnets and node subnets may overlap if explicitly approved; duplicates within either input are rejected.

Reference composition additionally requires the selected approved_options entry to match the exact VPC and subnet sets. Current YAML conformity=pending and approved_options={} fail closed. No fictitious segment is provided. NACL, route table correctness, address exhaustion, available AZs, AWS-reserved subnets, workload IP usage, endpoint policies and service availability require later real checks. DNS/route review flags cannot certify those facts automatically.

## Inputs

`vpc_id`, `cluster_subnet_ids`, `node_subnet_ids`, `conformity`, `connectivity`. See variables.tf for exact types, validations and optional defaults. Required inputs have no guessed environment values.

## Outputs

`vpc_id`, `cluster_subnet_ids`, `node_subnet_ids`, `connectivity`.

Terraform >=1.9,<2; provider AWS pinned to 6.20.0. See ../../../README.md for validation and approval boundaries.
