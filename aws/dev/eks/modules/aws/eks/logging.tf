resource "aws_cloudwatch_log_group" "control_plane" {
  count             = var.log_retention_days == null ? 0 : 1
  name              = "/aws/eks/${var.name}/cluster"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
  tags              = var.tags
}
