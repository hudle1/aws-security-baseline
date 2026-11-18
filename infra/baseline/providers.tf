provider "aws" {
  region = "us-east-1"

  # No `profile` here on purpose: credentials come from AWS_PROFILE (sandbox-admin).
  # Nothing account-specific is committed.
  #
  # Safety interlock: Terraform refuses to run if the credentials belong to any
  # account not in this list, so this stack can never touch another account.
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Project   = "aws-security-baseline"
      Stack     = "baseline" # guardrails uses "guardrails"; the tag shows which stack owns a resource
      ManagedBy = "terraform"
    }
  }
}
