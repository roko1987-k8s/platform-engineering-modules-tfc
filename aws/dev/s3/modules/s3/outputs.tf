output "bucket" {
  description = "Bucket ID, preserving the original output contract."
  value       = aws_s3_bucket.state.id
}

output "bucket_arn" {
  description = "Bucket ARN for reviewed consumer policies."
  value       = aws_s3_bucket.state.arn
}
