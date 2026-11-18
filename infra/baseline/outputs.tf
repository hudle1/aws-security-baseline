output "log_bucket_name" {
  description = "Name of the shared log-archive bucket."
  value       = aws_s3_bucket.logs.id
}

output "cloudtrail_name" {
  description = "Name of the CloudTrail trail."
  value       = aws_cloudtrail.main.name
}

output "cloudtrail_kms_key_alias" {
  description = "Alias of the CloudTrail KMS key."
  value       = aws_kms_alias.cloudtrail.name
}
