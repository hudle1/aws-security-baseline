# SNS alert topic KMS key (decision b: one key per service; decision Q-p).
# EventBridge cannot publish to a topic encrypted with the AWS-managed aws/sns key,
# because that key's policy can't be edited to grant EventBridge access. A
# customer-managed key is the only way to have an encrypted topic AND working alerts.

data "aws_iam_policy_document" "alerts_key" {
  #checkov:skip=CKV_AWS_109: Statement 1 is the standard "enable IAM permissions" root statement. Without it the key can be locked out. See docs/components/kms-alerts-key.md.
  #checkov:skip=CKV_AWS_111: Same statement. "*" in a key policy means "this key" only.
  #checkov:skip=CKV_AWS_356: Same reason. In a key policy the resource is always this key.
  # 1. Account root = "delegate to IAM" (same reasoning as the CloudTrail key).
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

  # 2. EventBridge must be able to encrypt the message it publishes (GenerateDataKey)
  #    and SNS must be able to read it back to deliver it (Decrypt).
  #    NO aws:SourceArn / aws:SourceAccount condition here on purpose: AWS documents
  #    that those conditions break EventBridge -> encrypted SNS delivery. Scoping is
  #    done in the TOPIC policy instead (only our rules may publish). Residual risk:
  #    the events service principal could in theory use this key for another caller's
  #    request, but it can only encrypt/decrypt alert text, and the topic accepts
  #    publishes from nobody but our rules.
  statement {
    sid       = "AllowEventBridgeToUseKeyForAlerts"
    effect    = "Allow"
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "alerts" {
  description = "Encrypts the baseline security-alert SNS topic"

  enable_key_rotation     = true # CIS 3.6 / KMS.4
  deletion_window_in_days = 7    # minimum; cancellable (threat model #4)

  policy = data.aws_iam_policy_document.alerts_key.json
}

resource "aws_kms_alias" "alerts" {
  name          = "alias/baseline-alerts"
  target_key_id = aws_kms_key.alerts.key_id
}
