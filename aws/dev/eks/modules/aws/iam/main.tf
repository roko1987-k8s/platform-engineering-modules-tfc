data "aws_partition" "current" {}
locals {
  trust = {
    cluster = { Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "eks.amazonaws.com" } }] }
    nodes   = { Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ec2.amazonaws.com" } }] }
  }
  # AmazonEKS_CNI_Policy only for the EKS-bootstrapped (self-managed) vpc-cni.
  node_policies = toset(concat(["AmazonEKSWorkerNodePolicy", "AmazonEC2ContainerRegistryPullOnly"], var.node_cni_policy ? ["AmazonEKS_CNI_Policy"] : []))
}
resource "aws_iam_role" "cluster" {
  name                 = "${var.name}-cluster"
  assume_role_policy   = jsonencode(local.trust.cluster)
  permissions_boundary = var.permissions_boundary
  tags                 = var.tags
}
resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}
resource "aws_iam_role" "nodes" {
  for_each             = toset(["system", "user"])
  name                 = "${var.name}-${each.key}"
  assume_role_policy   = jsonencode(local.trust.nodes)
  permissions_boundary = var.permissions_boundary
  tags                 = var.tags
}
resource "aws_iam_role_policy_attachment" "nodes" {
  for_each   = { for pair in setproduct(["system", "user"], local.node_policies) : "${pair[0]}-${pair[1]}" => pair }
  role       = aws_iam_role.nodes[each.value[0]].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${each.value[1]}"
}
resource "aws_iam_role" "pod_identity" {
  for_each             = var.pod_identity_roles
  name                 = "${var.name}-${each.key}"
  assume_role_policy   = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "pods.eks.amazonaws.com" }, Action = ["sts:AssumeRole", "sts:TagSession"] }] })
  permissions_boundary = var.permissions_boundary
  tags                 = var.tags
}
resource "aws_iam_role_policy" "pod_identity" {
  for_each = var.pod_identity_roles
  role     = aws_iam_role.pod_identity[each.key].id
  policy   = each.value.policy_json
}

# AWS Load Balancer Controller (internal NLB of the Istio gateway), through EKS Pod
# Identity (aws-load-balancer-controller/aws-load-balancer-controller). Policy: the upstream
# docs/install/iam_policy.json of the controller version pinned in the tools catalog
# (v3.6.3), unchanged; its writes are scoped by the elbv2.k8s.aws/cluster tag. Under the
# workload boundary like every role of the composition.
resource "aws_iam_role" "lb_controller" {
  count                = var.lb_controller ? 1 : 0
  name                 = "${var.name}-lb-controller"
  assume_role_policy   = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "pods.eks.amazonaws.com" }, Action = ["sts:AssumeRole", "sts:TagSession"] }] })
  permissions_boundary = var.permissions_boundary
  tags                 = var.tags
}
resource "aws_iam_role_policy" "lb_controller" {
  count  = var.lb_controller ? 1 : 0
  name   = "aws-load-balancer-controller"
  role   = aws_iam_role.lb_controller[0].id
  policy = file("${path.module}/policies/aws-load-balancer-controller.json")
}
