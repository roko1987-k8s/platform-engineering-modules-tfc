variable "name" {
  description = "VPC name produced by the central naming module; never typed by a developer."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,99}$", var.name))
    error_message = "The VPC name must come from the central naming module."
  }
}

variable "subnet_names" {
  description = "Subnet names produced by the central naming module, one per CIDR and in the same order."
  type        = object({ cluster = list(string), node = list(string) })
  validation {
    condition = (
      length(var.subnet_names.cluster) == length(var.networking.cluster_subnet_cidrs) &&
      length(var.subnet_names.node) == length(var.networking.node_subnet_cidrs) &&
      length(distinct(concat(var.subnet_names.cluster, var.subnet_names.node))) == length(concat(var.subnet_names.cluster, var.subnet_names.node)) &&
      alltrue([for n in concat(var.subnet_names.cluster, var.subnet_names.node) : can(regex("^[a-z][a-z0-9-]{2,99}$", n))])
    )
    error_message = "Provide one unique central-naming subnet name per cluster and node CIDR."
  }
}

variable "region" {
  description = "Region from the central EKS catalog. The inherited provider and every AZ must belong to it."
  type        = string
  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "A catalog-authorized AWS region is required."
  }
}

# Single Networking input. Cloud Infrastructure / Networking assign the CIDRs and
# the approval reference; nothing here guesses or defaults a segment.
variable "networking" {
  description = "VPC CIDR, cluster/node subnet CIDRs and the Networking approval reference. Connectivity review is attested after the VPC exists."
  type = object({
    vpc_cidr             = string
    cluster_subnet_cidrs = list(string)
    node_subnet_cidrs    = list(string)
    approval_reference   = string
    connectivity = optional(object({
      routing_reviewed           = bool
      private_api_reachable      = bool
      dns_reviewed               = bool
      registry_sts_eks_reachable = bool
    }))
  })

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._:/-]{1,127}$", trimspace(var.networking.approval_reference)))
    error_message = "Networking must supply a non-empty approval reference (ticket or change ID)."
  }

  # Canonical IPv4 network address within AWS VPC size limits (/16 to /28).
  validation {
    condition = try(
      can(cidrnetmask(var.networking.vpc_cidr)) &&
      cidrsubnet(var.networking.vpc_cidr, 0, 0) == var.networking.vpc_cidr &&
      tonumber(split("/", var.networking.vpc_cidr)[1]) >= 16 &&
      tonumber(split("/", var.networking.vpc_cidr)[1]) <= 28,
      false
    )
    error_message = "vpc_cidr must be a canonical IPv4 network (host bits zero) between /16 and /28."
  }

  # Private address space only (RFC 1918): the cluster API stays private.
  validation {
    condition = try(anytrue([
      for parent in ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"] :
      tonumber(split("/", var.networking.vpc_cidr)[1]) >= tonumber(split("/", parent)[1]) &&
      cidrsubnet("${cidrhost(var.networking.vpc_cidr, 0)}/${split("/", parent)[1]}", 0, 0) == parent
    ]), false)
    error_message = "vpc_cidr must be inside RFC 1918 private space (10/8, 172.16/12, 192.168/16)."
  }

  validation {
    condition = (
      length(var.networking.cluster_subnet_cidrs) >= 2 && length(var.networking.cluster_subnet_cidrs) <= 6 &&
      length(var.networking.node_subnet_cidrs) >= 2 && length(var.networking.node_subnet_cidrs) <= 6
    )
    error_message = "Provide between two and six cluster subnet CIDRs and between two and six node subnet CIDRs."
  }

  # Every subnet: canonical IPv4, no smaller than /28, contained in the VPC CIDR.
  validation {
    condition = try(alltrue([
      for cidr in concat(var.networking.cluster_subnet_cidrs, var.networking.node_subnet_cidrs) :
      can(cidrnetmask(cidr)) &&
      cidrsubnet(cidr, 0, 0) == cidr &&
      tonumber(split("/", cidr)[1]) <= 28 &&
      tonumber(split("/", cidr)[1]) >= tonumber(split("/", var.networking.vpc_cidr)[1]) &&
      cidrsubnet("${cidrhost(cidr, 0)}/${split("/", var.networking.vpc_cidr)[1]}", 0, 0) == var.networking.vpc_cidr
    ]), false)
    error_message = "Every subnet CIDR must be a canonical IPv4 network no smaller than /28 inside vpc_cidr."
  }

  # No duplicates or overlaps between any two subnets (cluster or node).
  validation {
    condition = try(alltrue(flatten([
      for i, a in concat(var.networking.cluster_subnet_cidrs, var.networking.node_subnet_cidrs) : [
        for j, b in concat(var.networking.cluster_subnet_cidrs, var.networking.node_subnet_cidrs) :
        i == j || (
          cidrsubnet("${cidrhost(a, 0)}/${min(tonumber(split("/", a)[1]), tonumber(split("/", b)[1]))}", 0, 0) !=
          cidrsubnet("${cidrhost(b, 0)}/${min(tonumber(split("/", a)[1]), tonumber(split("/", b)[1]))}", 0, 0)
        )
      ]
    ])), false)
    error_message = "Subnet CIDRs must not repeat or overlap."
  }
}

variable "tags" {
  description = "Reviewed tags plus identity tags (team, application, environment) from the composition."
  type        = map(string)
  default     = {}
}
