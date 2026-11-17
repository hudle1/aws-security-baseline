# 1. Password policy: CIS v5.0.0 1.7/1.8 + Security Hub IAM.7
resource "aws_iam_account_password_policy" "this" {
  #checkov:skip=CKV_AWS_9: Deliberate. Forced 90-day expiry was dropped from CIS v5.0.0 and NIST SP 800-63B advises against it.
  minimum_password_length        = 20 # CIS 1.7: at least 14
  password_reuse_prevention      = 24 # CIS 1.8: remember last 24
  require_uppercase_characters   = true
  require_lowercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  # max_password_age intentionally unset: NIST SP 800-63B advises against
  # forced periodic rotation (it pushes users to weak, predictable passwords).
  # CIS v5 doesn't require it and IAM.7 passes without it.
}

# 2. Account-level S3 Block Public Access: overrides any bucket-level setting
resource "aws_s3_account_public_access_block" "this" {
  block_public_acls       = true # reject new public ACLs
  ignore_public_acls      = true # ignore any public ACLs that already exist
  block_public_policy     = true # reject bucket policies that grant public access
  restrict_public_buckets = true # block public/cross-account access via existing public policies
}

# 3. IAM Access Analyzer: free, flags resources shared outside this account
resource "aws_accessanalyzer_analyzer" "account" {
  analyzer_name = "account-external-access"
  type          = "ACCOUNT"
}

# 4. Bring the existing manual budget under Terraform (no duplicate, no gap)
import {
  to = aws_budgets_budget.monthly
  id = "${var.account_id}:monthly-10-usd"
}

resource "aws_budgets_budget" "monthly" {
  name         = "monthly-10-usd" # must match exactly, or Terraform replaces it
  budget_type  = "COST"
  limit_amount = tostring(var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # The account's default ("primary") billing view, as set on the existing budget. Matched so the import doesn't change it.
  billing_view_arn = "arn:aws:billing::${var.account_id}:billingview/primary"

  # Gross spend: credits and refunds are excluded, so credits can't mask a compromise-driven cost spike.
  # The provider requires `metrics` whenever `filter_expression` is set; this matches the live budget.
  metrics = ["UnblendedCost"]

  filter_expression {
    not {
      dimensions {
        key    = "RECORD_TYPE"
        values = ["Credit", "Refund"]
      }
    }
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_email]
  }
}