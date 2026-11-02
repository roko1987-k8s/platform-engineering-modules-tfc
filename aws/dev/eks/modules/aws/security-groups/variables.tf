variable "name" {
  type = string
}
variable "vpc_id" {
  type = string
}
variable "tags" {
  type = map(string)
}
variable "rules" {
  description = "Approved directed initiator flows. No CIDRs, wildcard protocols or DENY rules. Empty creates no rules."
  type        = map(object({ relation = string, source = string, destination = string, protocol = string, from_port = number, to_port = number, approval_reference = string }))
  default     = {}
  validation {
    condition     = alltrue([for id, r in var.rules : can(regex("^[A-Za-z0-9_-]+$", id)) && contains(["110", "111", "112", "eks-api", "eks-kubelet", "dns", "dependency"], r.relation) && contains(["system", "user", "control_plane"], r.source) && contains(concat(["system", "user", "control_plane"], keys(var.external_destinations)), r.destination) && contains(["tcp", "udp"], r.protocol) && r.from_port >= 1 && r.to_port <= 65535 && floor(r.from_port) == r.from_port && floor(r.to_port) == r.to_port && r.from_port <= r.to_port && trimspace(r.approval_reference) != ""])
    error_message = "Rules need explicit approved SG endpoints, TCP/UDP ports 1..65535, relation and approval reference."
  }
  validation {
    condition     = alltrue([for r in values(var.rules) : r.relation == "110" ? r.source == "system" && r.destination == "user" : r.relation == "111" ? r.source == "user" && r.destination == "system" : r.relation == "112" ? r.source == "user" && r.destination == "user" : r.relation == "eks-api" ? contains(["system", "user"], r.source) && r.destination == "control_plane" && r.protocol == "tcp" && r.from_port == 443 && r.to_port == 443 : r.relation == "eks-kubelet" ? r.source == "control_plane" && contains(["system", "user"], r.destination) && r.protocol == "tcp" && r.from_port == 10250 && r.to_port == 10250 : r.relation == "dns" ? contains(["system", "user"], r.source) && r.from_port == 53 && r.to_port == 53 : contains(keys(var.external_destinations), r.destination)])
    error_message = "A relationship must match its endpoints and the justified EKS API/kubelet/DNS contract."
  }
  validation {
    condition     = alltrue(flatten([for aid, a in var.rules : [for bid, b in var.rules : aid == bid || a.source != b.source || a.destination != b.destination || a.protocol != b.protocol || a.to_port < b.from_port || b.to_port < a.from_port]]))
    error_message = "Duplicate or overlapping permissions for the same directed SG/protocol pair are forbidden."
  }
}
variable "external_destinations" {
  description = "Reviewed endpoint SG IDs in the same VPC; no generic Internet destination."
  type        = map(string)
  default     = {}
  validation {
    condition     = alltrue([for k, id in var.external_destinations : !contains(["system", "user", "control_plane", "Any", "any"], k) && can(regex("^sg-([0-9a-f]{8}|[0-9a-f]{17})$", id))]) && length(distinct(values(var.external_destinations))) == length(var.external_destinations)
    error_message = "External destinations must be distinct SG IDs with non-reserved names."
  }
}
