data "aws_vpc" "approved" { id = var.vpc_id }
data "aws_subnet" "approved" {
  for_each = toset(concat(var.cluster_subnet_ids, var.node_subnet_ids))
  id       = each.value
  lifecycle {
    postcondition {
      condition     = self.vpc_id == var.vpc_id
      error_message = "Every subnet must belong to the approved VPC."
    }
    postcondition {
      condition     = !contains(var.node_subnet_ids, each.key) || !self.map_public_ip_on_launch
      error_message = "Node subnets must not auto-assign public IP addresses."
    }
  }
}
resource "terraform_data" "validation" {
  input = var.connectivity.approval_reference
  lifecycle {
    precondition {
      condition     = length(toset([for id in var.cluster_subnet_ids : data.aws_subnet.approved[id].availability_zone_id])) >= 2 && length(toset([for id in var.node_subnet_ids : data.aws_subnet.approved[id].availability_zone_id])) >= 2
      error_message = "Cluster and node subnets each require two distinct availability zones."
    }
    precondition {
      condition     = data.aws_vpc.approved.enable_dns_support && data.aws_vpc.approved.enable_dns_hostnames
      error_message = "Private EKS endpoints require VPC DNS support and hostnames."
    }
  }
}
