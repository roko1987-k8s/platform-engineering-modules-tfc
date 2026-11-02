output "security_group_ids" {
  value = { for k, sg in aws_security_group.role : k => sg.id }
}
output "approved_rules" {
  value = var.rules
}
output "implicit_denials" {
  value = { "500" = "unmatched System ingress", "501" = "unmatched User ingress", "502" = "unmatched custom-SG egress; provisional policy" }
}
