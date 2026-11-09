# Creates the VPC and private subnets from Networking-assigned CIDRs only.
# No Internet Gateway, NAT Gateway, VPC endpoint or extra route table is created:
# egress architecture is a pending decision (see README).

data "aws_region" "current" {}

data "aws_availability_zones" "region" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  # Deterministic placement: sorted AZ names of the catalog region, using only as
  # many zones as the largest subnet set needs; subnet i goes to zone i mod count.
  zones_sorted = sort(data.aws_availability_zones.region.names)
  zone_count = min(
    length(local.zones_sorted),
    max(length(var.networking.cluster_subnet_cidrs), length(var.networking.node_subnet_cidrs)),
  )
  zones = slice(local.zones_sorted, 0, local.zone_count)

  subnets = merge(
    { for i, cidr in var.networking.cluster_subnet_cidrs : var.subnet_names.cluster[i] => {
      role              = "cluster"
      cidr              = cidr
      availability_zone = local.zones[i % local.zone_count]
    } },
    { for i, cidr in var.networking.node_subnet_cidrs : var.subnet_names.node[i] => {
      role              = "node"
      cidr              = cidr
      availability_zone = local.zones[i % local.zone_count]
    } },
  )

  connectivity_ready = try(
    var.networking.connectivity.routing_reviewed &&
    var.networking.connectivity.private_api_reachable &&
    var.networking.connectivity.dns_reviewed &&
    var.networking.connectivity.registry_sts_eks_reachable,
    false,
  )
}

resource "aws_vpc" "this" {
  cidr_block = var.networking.vpc_cidr
  # Private EKS endpoints require VPC DNS support and hostnames.
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(var.tags, { Name = var.name, NetworkingApproval = trimspace(var.networking.approval_reference) })

  lifecycle {
    precondition {
      condition     = data.aws_region.current.region == var.region
      error_message = "The inherited AWS provider region must match the catalog region."
    }
    precondition {
      condition     = alltrue([for zone in local.zones_sorted : startswith(zone, var.region)])
      error_message = "Every availability zone must belong to the catalog region."
    }
    precondition {
      condition     = local.zone_count >= 2
      error_message = "Cluster and node subnets each require two distinct availability zones in the catalog region."
    }
  }
}

resource "aws_subnet" "this" {
  for_each          = local.subnets
  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.availability_zone
  # Private subnets only: no automatic public IP on launch.
  map_public_ip_on_launch = false
  tags                    = merge(var.tags, { Name = each.key, SubnetRole = each.value.role })
}
