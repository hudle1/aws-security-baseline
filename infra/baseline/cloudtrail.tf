# The trail. CIS v5.0.0 3.1 (multi-region, CloudTrail.1), 3.2 (log file validation,
# CloudTrail.4), 3.5 (KMS encryption, CloudTrail.2). Decisions: d = management events
# only (no data events), e = no CloudWatch Logs (Tier 1).

resource "aws_cloudtrail" "main" {
  #checkov:skip=CKV_AWS_252: No SNS topic. Real-time notification is Tier 1 (decision e, docs/control-tiers.md).
  #checkov:skip=CKV2_AWS_10: No CloudWatch Logs integration. Tier 1 by decision e; CloudTrail.5 / CIS 3.4 is listed as fails-by-design.
  name           = var.trail_name
  s3_bucket_name = aws_s3_bucket.logs.id

  # Records activity in EVERY region, not just us-east-1, so an attacker's miners in
  # eu-west-1 still appear in the log (threat model #1, #10).
  is_multi_region_trail = true

  # Includes global services (IAM, STS, CloudFront), which have no region of their own
  # and are logged in us-east-1. Without it IAM changes would be missing.
  include_global_service_events = true

  # Writes an hourly signed digest of every log file's hash. Proves later whether a
  # log file was edited or deleted (threat model #2). Checked with
  # `aws cloudtrail validate-logs`; nothing checks it automatically.
  enable_log_file_validation = true

  # SSE-KMS with our key (CIS 3.5). Reading a log needs S3 read AND kms:Decrypt.
  kms_key_id = aws_kms_key.cloudtrail.arn

  enable_logging = true

  # Management events (control-plane API calls like CreateUser, StopLogging) only,
  # reads and writes. Data events (S3 object reads, Lambda invokes) are off by
  # decision d: they cost per event, and GuardDuty S3 Protection covers S3 in Phase 5.
  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  # Terraform can create the trail before the bucket policy exists, because nothing in
  # the trail's arguments references the policy. CloudTrail then fails at creation
  # (InsufficientS3BucketPolicyException). The explicit dependency forces the order.
  depends_on = [aws_s3_bucket_policy.logs]
}
