data "aws_partition" "current" {}
locals {
  trust = {
    cluster = { Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "eks.amazonaws.com" } }] }
    nodes   = { Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ec2.amazonaws.com" } }] }
  }
  node_policies = toset(["AmazonEKSWorkerNodePolicy", "AmazonEC2ContainerRegistryPullOnly"])
}
resource "aws_iam_role" "cluster" {
  name               = "${var.name}-cluster"
  assume_role_policy = jsonencode(local.trust.cluster)
  tags               = var.tags
}
resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}
resource "aws_iam_role" "nodes" {
  for_each           = toset(["system", "user"])
  name               = "${var.name}-${each.key}"
  assume_role_policy = jsonencode(local.trust.nodes)
  tags               = var.tags
}
resource "aws_iam_role_policy_attachment" "nodes" {
  for_each   = { for pair in setproduct(["system", "user"], local.node_policies) : "${pair[0]}-${pair[1]}" => pair }
  role       = aws_iam_role.nodes[each.value[0]].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${each.value[1]}"
}
resource "aws_iam_role" "pod_identity" {
  for_each           = var.pod_identity_roles
  name               = "${var.name}-${each.key}"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "pods.eks.amazonaws.com" }, Action = ["sts:AssumeRole", "sts:TagSession"] }] })
  tags               = var.tags
}
resource "aws_iam_role_policy" "pod_identity" {
  for_each = var.pod_identity_roles
  role     = aws_iam_role.pod_identity[each.key].id
  policy   = each.value.policy_json
}
