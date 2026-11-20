# AWS Config KMS key (decision b2: one key per service; CloudTrail has its own).
# Config writes snapshots/history to the shared log bucket, encrypted with THIS key
# (set as s3_kms_key_arn on the delivery channel), not the bucket's default key.

# AWS Config's service-linked role (decision Q-n). The recorder uses it to READ resource
# configurations. It is created explicitly so the recorder's role_arn is a known
# reference. It has no KMS permissions (AWS docs), which is why the key policy below
# grants the Config service principal instead of this role.
resource "aws_iam_service_linked_role" "config" {
  aws_service_name = "config.amazonaws.com"
  description      = "Lets AWS Config read resource configurations and deliver them (baseline stack)"
}

data "aws_iam_policy_document" "config_key" {
  #checkov:skip=CKV_AWS_109: Statement 1 is the standard "enable IAM permissions" root statement. Without it the key can be locked out. See docs/components/kms-config-key.md.
  #checkov:skip=CKV_AWS_111: Same statement. "*" in a key policy means "this key" only.
  #checkov:skip=CKV_AWS_356: Same reason. In a key policy the resource is always this key.
  # 1. Account root = "delegate to IAM" (same reasoning as the CloudTrail key,
  #    docs/components/kms-cloudtrail-key.md). Prevents a lockout if this policy is
  #    ever edited wrongly, and lets IAM admins read Config files (kms:Decrypt).
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

  # 2. AWS Config may create data keys for Config files and decrypt them. The principal
  #    is the Config SERVICE principal, not the service-linked role: AWS documents that
  #    the SLR has no KMS permissions, so Config delivers to S3 as config.amazonaws.com
  #    instead (https://docs.aws.amazon.com/config/latest/developerguide/s3-kms-key-policy.html).
  #    A first version of this statement named the SLR and delivery failed with
  #    InsufficientDeliveryPolicyException (docs/operations/troubleshooting.md #10).
  #    Two conditions close the confused-deputy gap (threat model #6): the request must
  #    be made on behalf of OUR account (aws:SourceAccount) and OUR delivery channel's
  #    region/account (aws:SourceArn). Unlike the SNS key, these conditions are
  #    supported here.
  statement {
    sid       = "AllowConfigServiceToEncryptAndDecrypt"
    effect    = "Allow"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = ["*"]

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
}

resource "aws_kms_key" "config" {
  description = "Encrypts AWS Config snapshots and history delivered to the log bucket"

  enable_key_rotation     = true # CIS 3.6 / KMS.4; old key material is kept so old files still decrypt
  deletion_window_in_days = 7    # minimum; deletion is a cancellable 7-day state (threat model #4)

  policy = data.aws_iam_policy_document.config_key.json
}

resource "aws_kms_alias" "config" {
  name          = "alias/baseline-config"
  target_key_id = aws_kms_key.config.key_id
}
