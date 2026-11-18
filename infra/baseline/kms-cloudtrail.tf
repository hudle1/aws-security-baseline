# CloudTrail KMS key (decision b: one key per service; the Config key arrives in Phase 5).
# CIS v5.0.0 3.5 / Security Hub CloudTrail.2 (trail encrypted with KMS), KMS.4 / CIS 3.6 (rotation).

data "aws_iam_policy_document" "cloudtrail_key" {
  #checkov:skip=CKV_AWS_109: Statement 1 is the standard "enable IAM permissions" root statement. Without it the key can be locked out. See docs/components/kms-cloudtrail-key.md.
  #checkov:skip=CKV_AWS_111: Same statement. "*" in a key policy means "this key" only.
  #checkov:skip=CKV_AWS_356: Same reason. In a key policy the resource is always this key.
  # 1. Account root = "delegate to IAM". NOT a statement that lets the root *user* do
  #    things; it says "IAM policies in this account may grant access to this key".
  #    Without it, only this key policy controls access, and one wrong edit leaves
  #    a key nobody can fix (lockout). Threat model #5 (key policy mistakes) and #4
  #    (recoverability). Residual: any IAM admin can use the key (threat model #3).
  statement {
    sid       = "EnableIAMPermissions"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"] # in a key policy, "*" means "this key"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.account_id}:root"]
    }
  }

  # 2. CloudTrail may create data keys (the keys that encrypt each log file), and
  #    only for THIS trail. Two conditions, both must hold:
  #      aws:SourceArn                          = who is calling (this trail, not another account's trail)
  #      kms:EncryptionContext:aws:cloudtrail:arn = what the key is used for (this trail's logs)
  #    Without them, any trail in any account could ask CloudTrail to use our key
  #    (confused deputy, threat model #6). GenerateDataKey* is encrypt-side only:
  #    it cannot read anything back.
  statement {
    sid       = "AllowCloudTrailToEncryptLogsForThisTrail"
    effect    = "Allow"
    actions   = ["kms:GenerateDataKey*"]
    resources = ["*"]

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
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = [local.trail_arn]
    }
  }

  # 3. CloudTrail checks the key exists and is usable when the trail is created or
  #    updated. Metadata only (no key material, no decrypt). Without it, create-trail
  #    can fail with InsufficientEncryptionPolicyException (availability, threat model #4).
  #    Pinned to this trail with aws:SourceArn, same as statement 2. AWS's own example
  #    has no condition here; if create-trail fails on the key, this is the first
  #    thing to check (see docs/operations/troubleshooting.md).
  statement {
    sid       = "AllowCloudTrailToDescribeKey"
    effect    = "Allow"
    actions   = ["kms:DescribeKey"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [local.trail_arn]
    }
  }

  # 4. Log readers in THIS account may decrypt, but only CloudTrail-encrypted data.
  #    kms:CallerAccount pins the caller to our account (a stranger's account can
  #    never match). The encryption-context condition means this statement cannot be
  #    used to decrypt anything that wasn't encrypted for a trail in our account.
  #    This is the pattern AWS documents for CloudTrail. Trade-off: because the
  #    principal is "*" plus an account condition, it grants decrypt to every
  #    principal in the account without needing an IAM allow. Fine for a one-admin
  #    sandbox; production would name a dedicated log-reader role (threat model #3).
  statement {
    sid       = "AllowAccountPrincipalsToDecryptCloudTrailLogs"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:ReEncryptFrom"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [var.account_id]
    }

    condition {
      test     = "StringLike"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = ["arn:aws:cloudtrail:*:${var.account_id}:trail/*"]
    }
  }
}

resource "aws_kms_key" "cloudtrail" {
  description = "Encrypts CloudTrail log files for the baseline trail"

  enable_key_rotation = true # new key material every year (CIS 3.6 / KMS.4); old material is kept, so old logs still decrypt
  # 7 is the minimum. Deletion is a 7-day cancellable state, not instant, so a
  # mistaken or malicious ScheduleKeyDeletion can be reversed (threat model #4).
  # Trade-off: a short window also gives an attacker/teardown less time to notice.
  deletion_window_in_days = 7

  policy = data.aws_iam_policy_document.cloudtrail_key.json
}

# An alias is a human-readable name for the key. Terraform, docs and the CLI use the
# alias; the key ID stays an implementation detail.
resource "aws_kms_alias" "cloudtrail" {
  name          = "alias/baseline-cloudtrail"
  target_key_id = aws_kms_key.cloudtrail.key_id
}
