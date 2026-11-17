# Access to a private EKS cluster (TD-049, option B). The endpoint stays private:
# people reach it through SSM port forwarding to a jump host without inbound ports.
#   - Platform Engineering roles: cluster admin (access entry, cluster scope).
#   - Bot role of THIS cluster: read-only view (no Secrets), assumable only by the
#     central bot identity AND only in a session tagged with this cluster's team
#     (Team = team_id): IAM itself blocks cross-team reads, whatever the caller says.
# The Terraform identity gets no Kubernetes access (bootstrap admin stays disabled).
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  access_policies = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy"
  bot_role_name   = substr("${var.name}-k8s-bot", 0, 64)
}

# --- Platform Engineering: cluster admin --------------------------------------
resource "aws_eks_access_entry" "platform" {
  for_each      = toset(var.platform_admin_role_arns)
  cluster_name  = var.cluster_name
  principal_arn = each.value
  type          = "STANDARD"
  tags          = var.tags
}

resource "aws_eks_access_policy_association" "platform" {
  for_each      = aws_eks_access_entry.platform
  cluster_name  = var.cluster_name
  principal_arn = each.value.principal_arn
  policy_arn    = "${local.access_policies}/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}

# --- Read-only bot role of this cluster ---------------------------------------
resource "aws_iam_role" "bot" {
  name                 = local.bot_role_name
  description          = "Read-only Kubernetes view of ${var.cluster_name} for the ADP bot (no Secrets)."
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = var.bot_assumer_arns }
      Action    = ["sts:AssumeRole", "sts:SetSourceIdentity"]
      # The broker session carries the requester's verified team as a session tag.
      Condition = { StringEquals = { "aws:PrincipalTag/Team" = var.team_id } }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "bot" {
  name = "eks-describe-and-ssm-tunnel"
  role = aws_iam_role.bot.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DescribeThisCluster"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = var.cluster_arn
      },
      {
        Sid    = "TunnelThroughThisJumpHost"
        Effect = "Allow"
        Action = ["ssm:StartSession"]
        Resource = [
          aws_instance.jump.arn,
          "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}::document/AWS-StartPortForwardingSessionToRemoteHost",
        ]
      },
      {
        Sid      = "OwnSessionsOnly"
        Effect   = "Allow"
        Action   = ["ssm:TerminateSession", "ssm:ResumeSession"]
        Resource = "arn:${data.aws_partition.current.partition}:ssm:*:*:session/$${aws:userid}-*"
      },
    ]
  })
}

resource "aws_eks_access_entry" "bot" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.bot.arn
  type          = "STANDARD"
  tags          = var.tags
}

resource "aws_eks_access_policy_association" "bot" {
  cluster_name  = var.cluster_name
  principal_arn = aws_eks_access_entry.bot.principal_arn
  policy_arn    = "${local.access_policies}/AmazonEKSViewPolicy"
  access_scope {
    type = "cluster"
  }
}

# --- SSM jump host: no inbound ports, no public IP ----------------------------
data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

resource "aws_iam_role" "jump" {
  name        = substr("${var.name}-ssm-jump", 0, 64)
  description = "SSM jump host of ${var.cluster_name} (Session Manager only)."
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "jump_ssm" {
  role       = aws_iam_role.jump.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "jump" {
  name = substr("${var.name}-ssm-jump", 0, 128)
  role = aws_iam_role.jump.name
  tags = var.tags
}

resource "aws_security_group" "jump" {
  name        = "${var.name}-ssm-jump"
  description = "SSM jump host: no inbound; HTTPS out to SSM (via NAT) and to the private EKS endpoint."
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-ssm-jump" })
}

resource "aws_vpc_security_group_egress_rule" "jump_https" {
  security_group_id = aws_security_group.jump.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "HTTPS to SSM endpoints (NAT) and the private EKS API"
  tags              = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "cluster_from_jump" {
  security_group_id            = var.cluster_security_group_id
  referenced_security_group_id = aws_security_group.jump.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "Kubernetes API from the SSM jump host only"
  tags                         = var.tags
}

resource "aws_instance" "jump" {
  ami                         = nonsensitive(data.aws_ssm_parameter.al2023_arm64.value)
  instance_type               = var.jump_instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.jump.id]
  iam_instance_profile        = aws_iam_instance_profile.jump.name
  associate_public_ip_address = false
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }
  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = 8
  }
  tags        = merge(var.tags, { Name = "${var.name}-ssm-jump", AdpAccess = "ssm-jump", EksCluster = var.cluster_name })
  volume_tags = var.tags
  lifecycle {
    # A newer AMI must not replace the host on every plan; rotate it deliberately.
    ignore_changes = [ami]
  }
}
