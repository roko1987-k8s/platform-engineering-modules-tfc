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
