variable "rules_catalog" {
  description = "network/rules.yaml of the central repository (decoded): rules defined once for every cloud."
  type        = any
  validation {
    condition = try(var.rules_catalog.schema == "adp-network-rules-v1", false) && alltrue([for id, r in var.rules_catalog.rules :
      can(regex("^1[0-4][0-9]$", id))
      && length(r.sources) > 0 && length(r.destinations) > 0
      && alltrue([for e in concat(r.sources, r.destinations) : contains(var.rules_catalog.endpoints, e)])
      && !contains(r.destinations, "any")
      && contains(["tcp", "udp", "all"], r.protocol)
      && (r.protocol == "all" ? length(try(r.ports, [])) == 0 : (try(r.status, "active") == "pending" || length(r.ports) > 0))
      && alltrue([for p in try(r.ports, []) : can(regex("^[0-9]{1,5}(-[0-9]{1,5})?$", p))])
      && contains(["active", "pending"], try(r.status, "active"))
    ])
    error_message = "network/rules.yaml: schema adp-network-rules-v1, base RuleIds 100-149, known endpoints, never any as destination, tcp/udp with ports or all without ports."
  }
}
variable "name" {
  description = "Base name of the instance security groups (module.naming names.sg); suffixes -system, -user, -ingress."
  type        = string
  validation {
    condition     = can(regex("^sg[a-z0-9]+$", var.name))
    error_message = "The security group base name comes from module.naming (prefix sg)."
  }
}
variable "cluster_name" {
  type = string
}
variable "cluster_security_group_id" {
  description = "EKS-created cluster security group (control plane only); the module adds rules 100/101 on it."
  type        = string
}
variable "vpc_id" {
  type = string
}
variable "jump_enabled" {
  description = "Whether the SSM jump host exists (known at plan time; the group ID is not)."
  type        = bool
  default     = false
}
variable "jump_security_group_id" {
  description = "SSM jump host security group (modules/aws/access); null when no access was injected."
  type        = string
  default     = null
}
variable "tags" {
  type = map(string)
}
variable "external_sources" {
  description = "Reviewed source SG IDs in the same VPC that custom rules may reference (e.g. a VPC endpoint or another service)."
  type        = map(string)
  default     = {}
  validation {
    condition     = alltrue([for k, id in var.external_sources : !contains(["system", "user", "lb", "control_plane", "jump", "any", "Any"], k) && can(regex("^sg-([0-9a-f]{8}|[0-9a-f]{17})$", id))]) && length(distinct(values(var.external_sources))) == length(var.external_sources)
    error_message = "External sources must be distinct SG IDs with non-reserved names."
  }
}
variable "custom_rules" {
  description = "Approved custom rules, RuleId within rules_catalog.custom_range (150-199: between the base allows and the 210/212 denials). One entry per logical rule with all its ports (\"N\" or \"N-M\"); TCP/UDP only, no CIDR, no -1, no deny."
  type        = map(object({ rule = string, source = string, destination = string, protocol = string, ports = list(string), approval_reference = string }))
  default     = {}
  validation {
    condition = alltrue([for id, r in var.custom_rules :
      can(regex("^[A-Za-z0-9_-]+$", id))
      && can(tonumber(r.rule)) && tonumber(r.rule) >= var.rules_catalog.custom_range.from && tonumber(r.rule) <= var.rules_catalog.custom_range.to
      && contains(concat(["system", "user", "lb", "control_plane"], keys(var.external_sources)), r.source)
      && contains(["system", "user", "lb"], r.destination)
      && contains(["tcp", "udp"], r.protocol)
      && length(r.ports) > 0 && length(distinct(r.ports)) == length(r.ports)
      && alltrue([for p in r.ports : can(regex("^[0-9]{1,5}(-[0-9]{1,5})?$", p)) && tonumber(split("-", p)[0]) >= 1 && tonumber(element(split("-", p), length(split("-", p)) - 1)) <= 65535 && tonumber(split("-", p)[0]) <= tonumber(element(split("-", p), length(split("-", p)) - 1))])
      && trimspace(r.approval_reference) != ""
    ])
    error_message = "Custom rules: RuleId in the catalogue custom_range (150-199), known source and destination, tcp/udp, at least one port (\"N\" or \"N-M\", 1..65535) and an approval reference."
  }
  validation {
    condition     = length(distinct([for r in values(var.custom_rules) : r.rule])) == length(var.custom_rules)
    error_message = "Each custom rule needs its own RuleId."
  }
  validation {
    condition = alltrue(flatten([for aid, a in var.custom_rules : [for bid, b in var.custom_rules : [for pa in a.ports : [for pb in b.ports :
      (aid == bid && pa == pb) || a.source != b.source || a.destination != b.destination || a.protocol != b.protocol
      || tonumber(element(split("-", pa), length(split("-", pa)) - 1)) < tonumber(split("-", pb)[0])
      || tonumber(element(split("-", pb), length(split("-", pb)) - 1)) < tonumber(split("-", pa)[0])
    ]]]]))
    error_message = "Duplicate or overlapping ports for the same source, destination and protocol are forbidden (also inside one rule)."
  }
}
