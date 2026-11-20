# AWS Config: records configuration history of the security-relevant resource types
# and delivers it to the shared log bucket. Security Hub controls are evaluated by
# Config rules, so Security Hub depends on this (securityhub.tf).
# Decisions: Q-n service-linked role, Q-m continuous recording, b2 own KMS key.

resource "aws_config_configuration_recorder" "main" {
  #checkov:skip=CKV2_AWS_48: Deliberately limited resource types (CLAUDE.md Phase 5, cost). Config.1 is listed as fails-by-design in docs/control-tiers.md (Tier 1).
  name     = "baseline-recorder"
  role_arn = aws_iam_service_linked_role.config.arn

  # Only the types the threat model and interview answers depend on (CLAUDE.md,
  # Phase 5). Recording everything costs per item and adds noise a one-person sandbox
  # cannot triage. The IAM types are global; they are recorded in this (home) region.
  recording_group {
    all_supported                 = false
    include_global_resource_types = false # deprecated flag; the explicit list below is what counts
    resource_types = [
      "AWS::S3::Bucket",
      "AWS::KMS::Key",
      "AWS::CloudTrail::Trail",
      "AWS::IAM::Role",
      "AWS::IAM::Policy",
      "AWS::IAM::User",
      "AWS::IAM::Group",
    ]
  }

  # CONTINUOUS = a configuration item is written within minutes of each change, billed
  # only when something changes ($0.003/item). DAILY would delay detection by up to 24h
  # and costs $0.012/item (decision Q-m, threat model #7).
  recording_mode {
    recording_frequency = "CONTINUOUS"
  }
}

# Where Config delivers. No s3_key_prefix on purpose: with no prefix Config writes to
# AWSLogs/<account>/Config/..., which is exactly the prefix the bucket policy allows.
# A custom prefix would put files somewhere the policy denies, and delivery would fail.
resource "aws_config_delivery_channel" "main" {
  name           = "baseline-delivery"
  s3_bucket_name = aws_s3_bucket.logs.id

  # Encrypt Config files with the Config key, not the bucket's default (CloudTrail) key.
  s3_kms_key_arn = aws_kms_key.config.arn

  # The recorder must exist first, and the bucket policy must already allow delivery.
  depends_on = [
    aws_config_configuration_recorder.main,
    aws_s3_bucket_policy.logs,
  ]
}

# Turns recording on. A recorder that exists but is not started records nothing.
# Order: delivery channel first, because starting a recorder without one is an error.
resource "aws_config_configuration_recorder_status" "main" {
  #checkov:skip=CKV2_AWS_45: Same reason as CKV2_AWS_48: limited resource types by design (docs/control-tiers.md, Config.1).
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main]
}
