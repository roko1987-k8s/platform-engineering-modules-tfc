# No agents, log collectors or additional infrastructure are created.
# Optional contract is consumed later by an approved observability integration.
resource "terraform_data" "contract" {
  count = var.enabled ? 1 : 0
  input = { cluster_name = var.cluster_name, control_plane_log_group = var.log_group_name, namespace = "ContainerInsights", metrics = var.metrics }
  lifecycle {
    precondition {
      condition     = trimspace(var.approval_reference) != "" && length(var.metrics) > 0
      error_message = "An explicit observability approval and selected metrics are required."
    }
  }
}
