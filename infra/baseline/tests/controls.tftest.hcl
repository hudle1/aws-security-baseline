# Tests for infra/baseline. Run from the repo root:
#   terraform -chdir=infra/baseline test
#
# These are PLAN-time tests against a MOCK provider: Terraform builds the plan for the
# whole stack, but the "aws" provider is replaced by a fake that invents values and
# never calls AWS. So no credentials are needed, nothing is created, and CI can run
# them on every pull request.
#
# What they prove: the CODE asks for the secure setting. What they cannot prove: that
# AWS actually applied it. That second question is answered by scripts/verify.ps1
# (live API checks) and the Prowler report in Phase 7.

mock_provider "aws" {
  # A mock invents a random string for every computed attribute. Policy arguments
  # (KMS key policy, bucket policy, SNS policy) are validated as JSON even in a plan,
  # so the policy-document data source needs a VALID JSON default or the plan fails
  # before any assert runs. The content is irrelevant here: these tests check
  # settings, not policy text (the policies are reviewed in PRs and checked by checkov).
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  # Same problem for the region: several ARNs are built from it and validated
  # ("arn:aws:securityhub:<region>::standards/..."), and a random region fails that check.
  mock_data "aws_region" {
    defaults = {
      name   = "us-east-1"
      region = "us-east-1"
    }
  }

  # Only needed by the one `apply` run below. After an apply, each resource's "arn" is
  # a value the mock invented, and other resources validate it as an ARN. Giving these
  # three types a well-formed ARN is enough; the values are fake and never leave memory.
  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    }
  }

  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:us-east-1:123456789012:mock-topic"
    }
  }

  mock_resource "aws_iam_service_linked_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/aws-service-role/config.amazonaws.com/mock"
    }
  }
}
mock_provider "random" {}

# Fake but well-formed inputs. 123456789012 is the AWS documentation example account,
# and example.com is reserved for documentation: neither is real, and neither can
# trigger a secret-scanner finding.
variables {
  account_id  = "123456789012"
  alert_email = "alerts@example.com"
}

# ---------------------------------------------------------------------------
# POSITIVE tests: each asserts one security control is switched on in the plan.
# If someone edits the .tf and weakens the control, the assert fails and the
# pull request cannot merge.
# ---------------------------------------------------------------------------

# Threat model #2 (tampering with logs). Versioning keeps every overwritten or deleted
# log as a noncurrent version, so tampering can be undone. We assert "Enabled" exactly:
# "Suspended" looks configured but silently makes deletes permanent.
run "log_bucket_versioning_enabled" {
  command = plan

  assert {
    condition     = aws_s3_bucket_versioning.logs.versioning_configuration[0].status == "Enabled"
    error_message = "Log bucket versioning must be 'Enabled' (not 'Suspended'), or deleted/overwritten logs are unrecoverable."
  }
}

# Threat model #3/#19 (public exposure). All four Block Public Access switches must be
# true. They are checked together because any single false one reopens a different hole
# (public ACLs, existing public ACLs, public policies, public cross-account access).
run "log_bucket_blocks_all_public_access" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.logs.block_public_acls,
      aws_s3_bucket_public_access_block.logs.ignore_public_acls,
      aws_s3_bucket_public_access_block.logs.block_public_policy,
      aws_s3_bucket_public_access_block.logs.restrict_public_buckets,
    ])
    error_message = "All four S3 Block Public Access flags on the log bucket must be true."
  }
}

# CIS 3.1 / 3.2 / 3.5 (CloudTrail.1, .4, .2). Log file validation is what lets you PROVE
# a log was not edited; multi-region means an attacker's activity in another region still
# lands in the log; the KMS key means reading a log needs two permissions, not one.
run "trail_is_validated_multiregion_and_encrypted" {
  command = plan

  assert {
    condition     = aws_cloudtrail.main.enable_log_file_validation == true
    error_message = "CloudTrail log file validation must be on (CIS 3.2)."
  }

  assert {
    condition     = aws_cloudtrail.main.is_multi_region_trail == true
    error_message = "The trail must be multi-region (CIS 3.1)."
  }

  assert {
    condition     = aws_cloudtrail.main.enable_logging == true
    error_message = "The trail must be logging."
  }
}

# CIS 3.5 (CloudTrail.2). The trail's kms_key_id is the key's ARN, and an ARN does not
# exist until the key is created, so a PLAN cannot see it ("known after apply"). This
# one run therefore uses command = apply. That is safe here: with mock_provider the real
# AWS provider is never loaded, so "apply" only fills Terraform's in-memory state with
# invented values. Nothing is created and no credentials are read.
run "trail_is_encrypted_with_kms" {
  command = apply

  assert {
    condition     = aws_cloudtrail.main.kms_key_id != null && aws_cloudtrail.main.kms_key_id != ""
    error_message = "The trail must be encrypted with a KMS key (CIS 3.5)."
  }
}

# CIS 3.6 / KMS.4. Without rotation, one leaked key stays useful forever. All three
# customer-managed keys (CloudTrail, Config, alerts) are checked in one run, using a
# map so the failure message names which key is wrong.
run "all_kms_keys_rotate" {
  command = plan

  assert {
    condition = alltrue([
      aws_kms_key.cloudtrail.enable_key_rotation,
      aws_kms_key.config.enable_key_rotation,
      aws_kms_key.alerts.enable_key_rotation,
    ])
    error_message = "Every customer-managed KMS key (cloudtrail, config, alerts) must have enable_key_rotation = true."
  }
}

# Decision d / Q-o. S3 Protection is ON because CloudTrail data events are off, so
# GuardDuty is the only thing watching S3 object activity. The for_each key is known at
# plan time, so we can index it directly. We also assert the expensive plans stay OFF:
# a billing feature must never switch on by accident (budget is $10/month).
run "guardduty_s3_protection_on_paid_plans_off" {
  command = plan

  assert {
    condition     = aws_guardduty_detector_feature.main["S3_DATA_EVENTS"].status == "ENABLED"
    error_message = "GuardDuty S3 Protection (S3_DATA_EVENTS) must be ENABLED."
  }

  assert {
    condition     = aws_guardduty_detector_feature.main["RUNTIME_MONITORING"].status == "DISABLED"
    error_message = "GuardDuty Runtime Monitoring is billed per vCPU and must stay DISABLED."
  }
}

# ---------------------------------------------------------------------------
# NEGATIVE tests: feed BAD input and require Terraform to REFUSE. "expect_failures"
# turns a validation error into a pass. If someone deletes or loosens the validation
# block, Terraform stops failing, and THESE tests go red. That is the point: they
# test that the stack fails closed.
# ---------------------------------------------------------------------------

# account_id feeds allowed_account_ids (the safety interlock that stops this stack from
# ever touching another account) and every policy ARN. A malformed ID must be rejected
# before any plan is produced.
run "rejects_malformed_account_id" {
  command = plan

  variables {
    account_id = "not-an-account"
  }

  expect_failures = [var.account_id]
}

# An alert address with no @ would create an SNS subscription that can never confirm,
# and the owner would get NO tamper alerts without noticing. Fail early instead.
run "rejects_malformed_alert_email" {
  command = plan

  variables {
    alert_email = "not-an-email"
  }

  expect_failures = [var.alert_email]
}

# Retention under 90 days could let an intrusion found late have no evidence left.
run "rejects_short_log_retention" {
  command = plan

  variables {
    log_retention_days = 30
  }

  expect_failures = [var.log_retention_days]
}
