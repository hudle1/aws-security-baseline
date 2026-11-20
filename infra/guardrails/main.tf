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
# ---------------------------------------------------------------------------
# Quick wins: four free account settings that fix failing Security Hub controls
# (Phase 5 scorecard, 2026-11-19). Decision Q-r. All are free.
# ---------------------------------------------------------------------------

data "aws_region" "current" {}

# 5. EBS default encryption: Security Hub EC2.7 (FSBP + CIS v5.0.0).
#    Every NEW EBS volume (and every snapshot copy) in this region is encrypted, even
#    if the person launching an instance forgets to ask. Without it an unencrypted
#    volume can hold data in the clear, and a leaked snapshot is readable. It uses the
#    AWS-managed key aws/ebs (free). Existing volumes are not changed; the sandbox has
#    none. Regional: it applies to us-east-1 only, like everything else in this stack.
resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}

# 6. Security contact: Security Hub Account.1 (FSBP + CIS v5.0.0).
#    AWS sends security notices (abuse reports, compromised-credential warnings) to
#    this contact. Without one they can go to an old billing mailbox nobody watches.
#    Name, email and phone are variables in guardrails.tfvars (gitignored) so no
#    personal details are committed. No contact exists today, so this creates one
#    (nothing to import).
resource "aws_account_alternate_contact" "security" {
  alternate_contact_type = "SECURITY"
  name                   = var.security_contact_name
  title                  = "Security Contact" # the provider requires a title; a fixed, non-personal value
  email_address          = var.security_contact_email
  phone_number           = var.security_contact_phone
}

# 7. Support role: Security Hub IAM.18 (CIS v5.0.0).
#    CIS wants a role that can manage incidents with AWS Support, so that support is
#    not handled with the admin role. The check passes when the AWSSupportAccess AWS
#    managed policy is attached to a role.
#    Trust: ONLY principals in this account (the account root = "any IAM principal
#    here that its own policy allows to assume it"). No external principals, so Access
#    Analyzer will not flag it. There is deliberately no aws:MultiFactorAuthPresent
#    condition: IAM Identity Center (SSO) sessions do not carry that flag, so it would
#    make the role impossible to assume. MFA is enforced earlier, at SSO login.
data "aws_iam_policy_document" "support_trust" {
  statement {
    sid     = "AllowThisAccountToAssume"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.account_id}:root"]
    }
  }
}

resource "aws_iam_role" "support" {
  name               = "aws-support-access"
  description        = "Manage incidents with AWS Support (CIS v5.0.0 IAM.18). No other permissions."
  assume_role_policy = data.aws_iam_policy_document.support_trust.json

  # Short sessions: a support case does not need a long-lived session (the default is 1 hour).
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "support" {
  role       = aws_iam_role.support.name
  policy_arn = "arn:aws:iam::aws:policy/AWSSupportAccess"
}

# 8. Block public sharing of SSM documents: Security Hub SSM.7 (FSBP, CRITICAL).
#    By default an account may share its Systems Manager documents with everyone.
#    A document can contain commands, parameters and sometimes internal names. "Disable"
#    turns public sharing off for this region. The sandbox has no SSM documents, so
#    nothing changes today; it only closes the door. setting_id is the setting's ARN.
resource "aws_ssm_service_setting" "block_public_document_sharing" {
  setting_id    = "arn:aws:ssm:${data.aws_region.current.region}:${var.account_id}:servicesetting/ssm/documents/console/public-sharing-permission"
  setting_value = "Disable"
}
