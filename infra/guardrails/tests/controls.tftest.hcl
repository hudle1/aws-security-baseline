# Tests for infra/guardrails. Run from the repo root:
#   terraform -chdir=infra/guardrails test
#
# Plan-time tests against a MOCK provider: no AWS calls, no credentials, nothing created.
# They prove the CODE requests the secure setting; scripts/verify.ps1 and the Prowler
# report (Phase 7) prove AWS actually applied it. See infra/baseline/tests for the
# longer explanation of how mocks work.

mock_provider "aws" {
  # Policy arguments are validated as JSON even in a plan, and a mock invents a random
  # string for the policy-document data source. Give it valid JSON (content irrelevant).
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  # The SSM setting id and other ARNs are built from the region; a random region would
  # fail ARN validation.
  mock_data "aws_region" {
    defaults = {
      name   = "us-east-1"
      region = "us-east-1"
    }
  }
}

# The budget is brought under Terraform with an `import` block, and a mock provider
# cannot perform an import (there is no real budget to read). Overriding this one
# resource tells Terraform "treat it as already handled". The budget's own settings are
# not what these tests check; everything else in the stack is still planned normally.
override_resource {
  target = aws_budgets_budget.monthly
}

# Fake, well-formed inputs: 123456789012 is the AWS documentation example account, the
# addresses use example.com (reserved for documentation), and 555-01xx numbers are
# reserved as fictional. None of it is real or secret-shaped.
variables {
  account_id             = "123456789012"
  budget_email           = "budget@example.com"
  security_contact_name  = "Test Contact"
  security_contact_email = "security@example.com"
  security_contact_phone = "+1 702 555 0100"
}

# ---------------------------------------------------------------------------
# POSITIVE tests
# ---------------------------------------------------------------------------

# CIS 1.7 / IAM.7. The CIS floor is 14 characters; the stack sets 20. We assert the
# floor, not the exact value, so raising it later never breaks the test but lowering it
# below the benchmark does. Reuse >= 24 matches CIS 1.8.
run "password_policy_meets_cis_floor" {
  command = plan

  assert {
    condition     = aws_iam_account_password_policy.this.minimum_password_length >= 14
    error_message = "Password minimum length must be at least 14 (CIS 1.7)."
  }

  assert {
    condition     = aws_iam_account_password_policy.this.password_reuse_prevention >= 24
    error_message = "Password reuse prevention must remember at least 24 passwords (CIS 1.8)."
  }
}

# Account-level Block Public Access overrides any single bucket's setting, so it is the
# backstop if someone makes one bucket public by mistake. All four flags, together.
run "account_blocks_all_public_s3_access" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_account_public_access_block.this.block_public_acls,
      aws_s3_account_public_access_block.this.ignore_public_acls,
      aws_s3_account_public_access_block.this.block_public_policy,
      aws_s3_account_public_access_block.this.restrict_public_buckets,
    ])
    error_message = "All four account-level S3 Block Public Access flags must be true."
  }
}

# Security Hub EC2.7: new EBS volumes are encrypted even if the launcher forgets.
run "ebs_default_encryption_on" {
  command = plan

  assert {
    condition     = aws_ebs_encryption_by_default.this.enabled == true
    error_message = "EBS encryption by default must be enabled (Security Hub EC2.7)."
  }
}

# Security Hub SSM.7: a published SSM document must not be shareable with everyone.
run "ssm_public_sharing_disabled" {
  command = plan

  assert {
    condition     = aws_ssm_service_setting.block_public_document_sharing.setting_value == "Disable"
    error_message = "Public sharing of SSM documents must be 'Disable' (Security Hub SSM.7)."
  }
}

# ---------------------------------------------------------------------------
# NEGATIVE tests: bad input must be REFUSED (fail closed).
# ---------------------------------------------------------------------------

# account_id is the allowed_account_ids safety interlock. A wrong-shaped ID must stop
# the run before anything is planned, not become a silently useless interlock.
run "rejects_malformed_account_id" {
  command = plan

  variables {
    account_id = "1234"
  }

  expect_failures = [var.account_id]
}

# A budget with limit 0 or less would alert on nothing, or on everything.
run "rejects_non_positive_budget" {
  command = plan

  variables {
    budget_limit_usd = 0
  }

  expect_failures = [var.budget_limit_usd]
}

# Phone numbers go to AWS as the security contact; letters or symbols outside the
# allowed set are rejected by AWS at apply time (late, after a plan already looked fine).
# The validation catches it at plan time instead.
run "rejects_bad_security_phone" {
  command = plan

  variables {
    security_contact_phone = "call me maybe"
  }

  expect_failures = [var.security_contact_phone]
}
