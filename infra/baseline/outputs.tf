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

output "config_kms_key_alias" {
  description = "Alias of the AWS Config KMS key."
  value       = aws_kms_alias.config.name
}

output "alerts_kms_key_alias" {
  description = "Alias of the SNS alerts KMS key."
  value       = aws_kms_alias.alerts.name
}

output "alerts_topic_name" {
  description = "Name of the SNS topic that receives security alerts."
  value       = aws_sns_topic.alerts.name
}
