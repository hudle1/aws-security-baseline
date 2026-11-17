provider "aws" {
  region = "us-east-1"

  # No `profile` here on purpose: credentials come from the AWS_PROFILE
  # environment variable (sandbox-admin). Nothing account-specific is committed,
  # and CI without AWS_PROFILE simply cannot authenticate.
  #
  # Safety interlock: Terraform calls sts:GetCallerIdentity and refuses to run
  # if the credentials belong to any account not in this list.
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Project   = "aws-security-baseline"
      Stack     = "guardrails"
      ManagedBy = "terraform"
    }
  }
}
