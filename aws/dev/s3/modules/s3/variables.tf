variable "bucket_name" {
  description = "Explicitly approved bucket name; no name is generated automatically."
  type        = string
  nullable    = false
}

variable "tags" {
  description = "Explicit tags supplied by the consuming service or environment."
  type        = map(string)
  nullable    = false
}
