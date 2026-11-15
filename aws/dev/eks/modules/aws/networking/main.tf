# Creates the VPC, private subnets and the egress path from Networking-assigned
# CIDRs only: public subnets host the NAT Gateways (one per public subnet), an
# Internet Gateway, and route tables. No VPC endpoint, NACL or security group is
# created here; EKS security groups belong to the security-groups module.

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
    max(
      length(var.networking.public_subnet_cidrs),
      length(var.networking.cluster_subnet_cidrs),
      length(var.networking.node_subnet_cidrs),
    ),
  )
  zones = slice(local.zones_sorted, 0, local.zone_count)

  subnet_sets = {
    public  = var.networking.public_subnet_cidrs
    cluster = var.networking.cluster_subnet_cidrs
    node    = var.networking.node_subnet_cidrs
  }
  subnets = merge([
    for role, cidrs in local.subnet_sets : {
      for i, cidr in cidrs : var.subnet_names[role][i] => {
        role              = role
        cidr              = cidr
        availability_zone = local.zones[i % local.zone_count]
      }
    }
  ]...)
  public_subnets  = { for name, s in local.subnets : name => s if s.role == "public" }
  private_subnets = { for name, s in local.subnets : name => s if s.role != "public" }

  # Each private zone routes through the NAT in the same zone, or through the
  # first NAT (by name) when that zone has none (single-NAT design).
  nat_by_zone   = { for name, s in local.public_subnets : s.availability_zone => name... }
  private_zones = toset([for s in values(local.private_subnets) : s.availability_zone])
  private_route_nat = {
    for zone in local.private_zones : zone => (
      contains(keys(local.nat_by_zone), zone) ? sort(local.nat_by_zone[zone])[0] : sort(keys(local.public_subnets))[0]
    )
  }

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
  # No automatic public IP anywhere: NAT Gateways use Elastic IPs; nodes stay private.
  map_public_ip_on_launch = false
  tags                    = merge(var.tags, { Name = each.key, SubnetRole = each.value.role })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-igw" })
}

resource "aws_eip" "nat" {
  for_each = local.public_subnets
  domain   = "vpc"
  tags     = merge(var.tags, { Name = "${each.key}-nat" })
  # The address is only routable once the VPC has its Internet Gateway.
  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  for_each      = local.public_subnets
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.this[each.key].id
  tags          = merge(var.tags, { Name = "${each.key}-nat" })
  depends_on    = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each       = local.public_subnets
  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  for_each = local.private_zones
  vpc_id   = aws_vpc.this.id
  tags     = merge(var.tags, { Name = "${var.name}-private-${each.key}" })
}

resource "aws_route" "private_nat" {
  for_each               = local.private_route_nat
  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[each.value].id
}

resource "aws_route_table_association" "private" {
  for_each       = local.private_subnets
  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.private[each.value.availability_zone].id
}
