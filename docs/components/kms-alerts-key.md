# Component: alerts KMS key

**Stack:** `infra/baseline` · **Written:** Phase 5 · **Verified live:** 2026-11-19

## What it is

A customer-managed KMS key, alias `alias/baseline-alerts`, that encrypts the `baseline-security-alerts` SNS topic. Annual rotation on, 7-day deletion window.

## Why we have it

SNS topics should be encrypted at rest (Checkov `CKV_AWS_26`). The AWS-managed `aws/sns` key does not work here: its policy cannot be edited, so EventBridge cannot be granted use of it and alerts would silently never arrive (decision Q-p). Threat model #4 (key deleted or disabled) also applies: if this key is disabled, **alerts stop being delivered**. The `kms-tamper` alert covers it, because it watches any key.

## Configuration

| Setting | Value | Reason |
| --- | --- | --- |
| Key policy statement 1 | account root, `kms:*` | The standard "delegate to IAM" statement; prevents a lockout (same as [kms-cloudtrail-key.md](kms-cloudtrail-key.md)). Checkov `CKV_AWS_109/111/356` skipped on the policy document with that reason. |
| Key policy statement 2 | `events.amazonaws.com` may `kms:GenerateDataKey*` and `kms:Decrypt`, **no conditions** | EventBridge must encrypt the message and SNS must read it back. AWS documents that `aws:SourceAccount` / `aws:SourceArn` conditions here break delivery. The topic policy limits who can publish. See [alerts.md](alerts.md#trade-off-no-awssourceaccount-on-the-key-policy). |
| `enable_key_rotation` | `true` | CIS 3.6 / KMS.4. |
| `deletion_window_in_days` | 7 | Minimum; a cancellable state, not instant (threat model #4). |

## File that defines it

`infra/baseline/kms-alerts.tf`.

## How to verify it works

```powershell
aws sns get-topic-attributes --topic-arn <TOPIC_ARN> --region us-east-1 --profile sandbox-admin --query "Attributes.KmsMasterKeyId"
$kid = aws kms describe-key --key-id alias/baseline-alerts --region us-east-1 --profile sandbox-admin --query "KeyMetadata.KeyId" --output text
aws kms describe-key --key-id $kid --region us-east-1 --profile sandbox-admin --query "KeyMetadata.[KeyState,Enabled]"
aws kms get-key-rotation-status --key-id $kid --region us-east-1 --profile sandbox-admin --query "KeyRotationEnabled"
```

`get-key-rotation-status` and `get-key-policy` need the key **ID**; they reject an alias with `InvalidArnException`.

**Result on 2026-11-19:** the topic's `KmsMasterKeyId` is this key. Delivery through the encrypted topic works end to end: emails from the `kms-tamper` and `logbucket-tamper` rules arrived and rendered correctly. Key policy confirmed to contain only the two statements above. Rotation: `true` (checked 2026-11-19).

## How to change it safely

1. Never remove statement 2: alerts stop silently. Never add `aws:SourceAccount` / `aws:SourceArn` to it without a live test, and expect delivery to fail.
2. Keep the root statement, or one wrong edit locks the key.
3. Do not schedule it for deletion: SNS would fail to publish and alerts stop. If you must replace the key, change `kms_master_key_id` on the topic in the same apply.

## What breaks if it's removed

The topic can no longer encrypt or decrypt: every alert is lost, with no error shown to the person who is supposed to be warned. `FailedInvocations` on the rules is the only signal.

## Cost

About $1/month for a customer-managed key (KMS requests are negligible and free-tier covered at this volume). **Estimate, to verify in Cost Explorer.**

## Related controls

Checkov `CKV_AWS_26` (SNS encrypted). CIS v5.0.0 3.6 / Security Hub KMS.4 (rotation). SOC 2: CC6.1, CC6.7.
