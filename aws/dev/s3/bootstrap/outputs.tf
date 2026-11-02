output "bucket" {
  description = "Bucket ID, preserving the original bootstrap output."
  value       = module.s3.bucket
}

output "bucket_arn" {
  description = "Bucket ARN for reviewed consumer policies."
  value       = module.s3.bucket_arn
}
