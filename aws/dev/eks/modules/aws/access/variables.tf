variable "name" {
  description = "EKS name from module.naming; prefixes every resource of this module."
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster (module.eks)."
  type        = string
}

variable "cluster_arn" {
  description = "ARN of the EKS cluster; scopes the bot's eks:DescribeCluster."
  type        = string
}

variable "cluster_security_group_id" {
  description = "EKS-managed cluster security group; receives the 443 rule from the jump host only."
  type        = string
}

variable "vpc_id" {
  description = "VPC of the workspace."
  type        = string
}

variable "subnet_id" {
  description = "Private subnet for the SSM jump host (no public IP; egress through the existing NAT)."
  type        = string
}

variable "platform_admin_role_arns" {
  description = "IAM roles of Platform Engineering with cluster admin (never IAM users)."
  type        = list(string)
  validation {
    condition = length(var.platform_admin_role_arns) > 0 && alltrue([
      for arn in var.platform_admin_role_arns : can(regex("^arn:aws:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]{1,512}$", arn))
    ])
    error_message = "platform_admin_role_arns must be one or more IAM role ARNs."
  }
}

variable "bot_assumer_arns" {
  description = "IAM roles that may assume this cluster's read-only bot role (the central bot identity)."
  type        = list(string)
  validation {
    condition = length(var.bot_assumer_arns) > 0 && alltrue([
      for arn in var.bot_assumer_arns : can(regex("^arn:aws:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]{1,512}$", arn))
    ])
    error_message = "bot_assumer_arns must be one or more IAM role ARNs."
  }
}

variable "jump_instance_type" {
  description = "Instance type of the SSM jump host (ARM)."
  type        = string
  default     = "t4g.nano"
  validation {
    condition     = contains(["t4g.nano", "t4g.micro"], var.jump_instance_type)
    error_message = "jump_instance_type must be t4g.nano or t4g.micro."
  }
}

variable "tags" {
  description = "Identity tags (Team, ApplicationCode, Environment) applied to every taggable resource."
  type        = map(string)
}
