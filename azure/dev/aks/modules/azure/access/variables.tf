variable "cluster_id" {
  type = string
}
variable "readers" {
  description = "Read-only principals by purpose (e.g. sre_agent) -> Entra ID object ID. Never individual developers."
  type        = map(string)
  default     = {}
  validation {
    condition     = alltrue([for key, id in var.readers : can(regex("^[a-z][a-z0-9_]{0,31}$", key)) && can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", id))])
    error_message = "Readers are purpose keys mapped to Entra ID object IDs (GUID)."
  }
}
variable "name" {
  description = "names.aks from the naming module; prefixes the custom roles of this cluster."
  type        = string
}
variable "resource_group_id" {
  description = "Workspace resource group: scope and only assignable scope of the custom roles."
  type        = string
}
variable "admin_group_object_ids" {
  description = "Platform Engineering Entra ID admin groups (cluster admin on the cluster); they also get command invoke."
  type        = list(string)
  default     = []
}
variable "agents" {
  description = "Entra ID object IDs of this team's agent identities (bot, tools, cleanup); each is optional."
  type        = object({ bot = optional(string), tools = optional(string), cleanup = optional(string) })
  default     = {}
  validation {
    condition     = alltrue([for id in values(var.agents) : id == null || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", id))])
    error_message = "Agent identities are Entra ID object IDs (GUID)."
  }
}
