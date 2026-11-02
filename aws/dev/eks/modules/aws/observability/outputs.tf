output "integration" {
  value = var.enabled ? terraform_data.contract[0].output : null
}
