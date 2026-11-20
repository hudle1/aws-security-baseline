# Shared log-archive bucket (decision a: CloudTrail now, AWS Config in Phase 5, separate prefixes).

# Bucket names are global across all AWS accounts. A random suffix makes the name
# unique, and keeps the account ID out of a name that appears in logs, ARNs and
# screenshots. keepers is empty, so the suffix is generated once and never changes
# (a changed suffix would replace the bucket and its logs).
resource "random_id" "log_bucket_suffix" {
  byte_length = 4 # 4 bytes = 8 hex characters
}

resource "aws_s3_bucket" "logs" {
  #checkov:skip=CKV_AWS_18: Tier 1 exception (docs/control-tiers.md). Server access logging is not in CIS v5.0.0 or FSBP; it would need a second hardened bucket.
  #checkov:skip=CKV_AWS_144: Cross-region replication is a production improvement (separate log-archive account). Out of scope for a single-region sandbox.
  #checkov:skip=CKV2_AWS_62: Event notifications are Tier 1 (EventBridge alerting on tampering). Not in v1.
  bucket = "aws-security-baseline-logs-${random_id.log_bucket_suffix.hex}"

  # SANDBOX-ONLY TRADE-OFF. Lets `terraform destroy` delete the bucket even when it
  # holds logs (otherwise destroy fails on a non-empty bucket). The cost is that one
  # destroy erases the audit trail (threat model #12). Mitigations: every destroy
  # shows a plan and needs a human "yes". Production: false, logs in a separate
  # account that the workload pipeline cannot touch.
  force_destroy = true
}

# Turns ACLs off. The bucket owner (us) owns every object, even ones written by
# CloudTrail. Access is then controlled by the bucket policy alone, which removes
# a whole class of "someone set a public ACL" mistakes.
resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Bucket-level Block Public Access: the same four switches as the account-level
# setting in guardrails, set again here so the bucket stays protected even if
# someone weakens the account setting (threat model #3, #19).
resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# Versioning keeps every overwritten or deleted object as a noncurrent version, so
# tampering with a log file can be undone (threat model #2). "Suspended" would be a
# trap: new objects stop getting versions, so deletes become permanent while the
# bucket still looks configured. mfa_delete is left out on purpose: Terraform can't
# manage it without root MFA credentials, and the project has no root access keys.
resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Default encryption: every object is encrypted with the CloudTrail key, even if a
# writer forgets to ask for it. (CloudTrail names the key itself on each write;
# Config will name its own key in Phase 5, decision b. This default only applies to
# writers that name no key.)
resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.cloudtrail.arn
    }

    # A bucket key makes S3 reuse one short-lived key per bucket instead of calling
    # KMS for every object. Cuts KMS request cost and volume by up to 99%.
    bucket_key_enabled = true
  }
}

# Retention. Trade-off for log_retention_days (default 365):
#   shorter (90) = cheaper, but an intrusion found after 3 months has no evidence;
#   longer  (365+) = covers the typical SOC 2 audit window and slow investigations.
#   A year of management events in a one-person sandbox is a few cents; the real
#   cost is in a busy production account. Digest files expire on the same schedule,
#   so log file validation only works inside this window.
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  # Lifecycle rules that touch noncurrent versions need versioning on first.
  depends_on = [aws_s3_bucket_versioning.logs]

  rule {
    id     = "expire-current-logs"
    status = "Enabled"

    filter {} # empty filter = every object in the bucket

    expiration {
      days = var.log_retention_days
    }

    # Overwritten or deleted versions are kept this long, then removed for good.
    # This is the window in which tampering can be undone (threat model #2).
    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_retention_days
    }

    # Half-finished uploads cost money and are never useful.
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # When versioning is on, "expiring" an object leaves a delete marker behind.
  # This rule removes markers that no longer hide any version.
  rule {
    id     = "remove-orphan-delete-markers"
    status = "Enabled"

    filter {}

    expiration {
      expired_object_delete_marker = true
    }
  }
}

data "aws_iam_policy_document" "logs_bucket" {
  # 1. CloudTrail asks "who owns this bucket?" before every delivery (GetBucketAcl).
  #    If this is missing, the trail can't be created (InsufficientS3BucketPolicyException).
  statement {
    sid       = "AWSCloudTrailAclCheck"
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.logs.arn]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    # Confused-deputy defense (threat model #6): the service principal is shared by
    # every CloudTrail customer. These two conditions limit it to THIS trail in
    # THIS account. Either alone would also work; both = defense in depth.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }

  # 2. CloudTrail may write log files and digest files, only under our account's
  #    CloudTrail prefixes. NOT AWSLogs/<account>/*: that would also let it write into
  #    the Config prefix (decision a: each service stays in its own prefix).
  #    CloudTrail uses two sibling folders: CloudTrail/ (logs) and CloudTrail-Digest/
  #    (validation digests).
  statement {
    sid     = "AWSCloudTrailWrite"
    effect  = "Allow"
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.logs.arn}/AWSLogs/${var.account_id}/CloudTrail/*",
      "${aws_s3_bucket.logs.arn}/AWSLogs/${var.account_id}/CloudTrail-Digest/*",
    ]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }

    # Required by CloudTrail even though ACLs are disabled: it sends this header, and
    # BucketOwnerEnforced accepts exactly this ACL value and nothing else.
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  # 3. Refuse any request that is not TLS. Deny always beats Allow, so this cannot be
  #    bypassed by another statement. Stops credentials/logs crossing the network in
  #    cleartext (threat model #3; Security Hub S3.5).
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.logs.arn, "${aws_s3_bucket.logs.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Statements 4-6 follow AWS's documented bucket policy for AWS Config delivery:
  # https://docs.aws.amazon.com/config/latest/developerguide/s3-bucket-policy.html
  # Same three statements, each with aws:SourceAccount, plus aws:SourceArn. AWS
  # documents SourceArn as supported: for the Config service principal it is always
  # arn:aws:config:<region>:<account>:*, so it limits delivery to a Config delivery
  # channel in OUR account and region (confused deputy, threat model #6).
  # History: the first apply failed with InsufficientDeliveryPolicyException. SourceArn
  # was suspected and removed, but it was NOT the cause; the cause was the Config KMS
  # key policy (see kms-config.tf and docs/operations/troubleshooting.md #10).

  # 4. Config asks "who owns this bucket?" before delivering (like statement 1 for CloudTrail).
  statement {
    sid       = "AWSConfigBucketPermissionsCheck"
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.logs.arn]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.config_source_arn]
    }
  }

  # 5. Config checks that the bucket exists and can be listed.
  statement {
    sid       = "AWSConfigBucketExistenceCheck"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.logs.arn]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.config_source_arn]
    }
  }

  # 6. Config may write its files, only under its own prefix AWSLogs/<account>/Config/
  #    (never widen to AWSLogs/<account>/*, decision a). bucket-owner-full-control is
  #    required even with ACLs disabled: BucketOwnerEnforced accepts exactly this value.
  statement {
    sid       = "AWSConfigBucketDelivery"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/AWSLogs/${var.account_id}/Config/*"]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.config_source_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.logs_bucket.json

  # Changing the policy and the public access block at the same moment can fail with
  # a 409 conflict. Applying the block first also means the policy is validated
  # against it (block_public_policy rejects a policy that grants public access).
  depends_on = [aws_s3_bucket_public_access_block.logs]
}
