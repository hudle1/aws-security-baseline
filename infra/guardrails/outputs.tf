# These reference the resource names you will create in main.tf
# (aws_iam_account_password_policy.this, etc.). Validate fails until they exist.

output "password_policy_min_length" {
  description = "Minimum IAM password length enforced on the account."
  value       = aws_iam_account_password_policy.this.minimum_password_length
}

output "s3_block_public_access" {
  description = "Account-level S3 Block Public Access settings."
  value = {
    block_public_acls       = aws_s3_account_public_access_block.this.block_public_acls
    block_public_policy     = aws_s3_account_public_access_block.this.block_public_policy
    ignore_public_acls      = aws_s3_account_public_access_block.this.ignore_public_acls
    restrict_public_buckets = aws_s3_account_public_access_block.this.restrict_public_buckets
  }
}

output "access_analyzer_name" {
  description = "Name of the account-level external access analyzer."
  value       = aws_accessanalyzer_analyzer.account.analyzer_name
}

output "budget_name" {
  description = "Name of the managed monthly cost budget."
  value       = aws_budgets_budget.monthly.name
}

output "ebs_encryption_by_default" {
  description = "Whether new EBS volumes in this region are encrypted by default (Security Hub EC2.7)."
  value       = aws_ebs_encryption_by_default.this.enabled
}

output "support_role_name" {
  description = "Name of the IAM role with AWSSupportAccess (Security Hub IAM.18)."
  value       = aws_iam_role.support.name
}

output "ssm_public_document_sharing" {
  description = "Value of the SSM public document sharing setting (Security Hub SSM.7): Disable = blocked."
  value       = aws_ssm_service_setting.block_public_document_sharing.setting_value
}
