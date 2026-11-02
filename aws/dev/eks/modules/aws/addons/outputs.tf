output "addons" {
  value = { for name, addon in merge(aws_eks_addon.managed, aws_eks_addon.identity_agent) : name => { arn = addon.arn, version = addon.addon_version } }
}
