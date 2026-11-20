# Component: AWS Config KMS key

**Stack:** `infra/baseline` · **Written:** Phase 5 · **Verified live:** 2026-11-19

## What it is

A customer-managed KMS key, alias `alias/baseline-config`, that encrypts what AWS Config writes into the shared [log bucket](log-bucket.md). One key per service (decision b2); the CloudTrail key stays separate. Annual rotation on, 7-day deletion window. It is named as `s3_kms_key_arn` on the Config delivery channel, so it overrides the bucket's default (CloudTrail) key for Config files.

## Why we have it

A key-policy mistake or a deleted key in one service must not affect the other (smaller blast radius, decision b2). Threat models: #4 (key deleted or disabled makes Config history unreadable and breaks delivery), #5 (key policy mistakes), #6 (confused deputy).

## Configuration

| Setting | Value | Reason |
| --- | --- | --- |
| Statement 1 | account root, `kms:*` | "Delegate to IAM"; prevents a lockout. Checkov `CKV_AWS_109/111/356` skipped on the policy document with that reason. |
| Statement 2 | `config.amazonaws.com` may `kms:GenerateDataKey` and `kms:Decrypt`, conditions `aws:SourceAccount` = this account and `aws:SourceArn` = `arn:aws:config:us-east-1:<ACCOUNT_ID>:*` | **The Config service-linked role has no KMS permissions (AWS documents this), so with an SLR, Config delivers to S3 as the service principal, not as the role.** The two conditions stop another account's Config from using our key (confused deputy). |
| `enable_key_rotation` | `true` | CIS 3.6 / KMS.4. |
| `deletion_window_in_days` | 7 | Minimum; cancellable. |

The key policy deliberately does **not** name the service-linked role. A first version did, and Config delivery failed (see [troubleshooting.md #10](../operations/troubleshooting.md#10-config-insufficientdeliverypolicyexception-creating-the-delivery-channel)).

## File that defines it

`infra/baseline/kms-config.tf` (key, alias, policy, and the explicit service-linked role resource). The `aws:SourceArn` value is `local.config_source_arn` in `locals.tf`.

## How to verify it works

```powershell
aws configservice describe-delivery-channels --region us-east-1 --profile sandbox-admin --query "DeliveryChannels[0].s3KmsKeyArn"
aws kms describe-key --key-id alias/baseline-config --region us-east-1 --profile sandbox-admin --query "KeyMetadata.Arn"
```

The two ARNs must match. **Result on 2026-11-19:** they match, and `describe-configuration-recorder-status` reports `recording: true`, `lastStatus: SUCCESS` (delivery to S3 with this key succeeded; the channel creation itself test-writes a file and would have failed otherwise). A delivered Config object (`.../Config/ConfigWritabilityCheckFile`) has `ServerSideEncryption` `aws:kms` and its `SSEKMSKeyId` equals this key (checked with `head-object`, 2026-11-19); 6 objects had been delivered at that point. Rotation: `true`.

## How to change it safely

1. Never remove statement 2: delivery fails and Config history stops reaching the bucket.
2. Keep both conditions. Dropping them widens who may use the key.
3. After any key-policy change, allow a few seconds to propagate; the AWS provider retries known propagation errors (troubleshooting #11).

## What breaks if it's removed

Config cannot write history or snapshots to the bucket (delivery errors). Recording continues but nothing is stored, and Security Hub rule evaluation may be affected.

## Cost

About $1/month. **Estimate, to verify in Cost Explorer.**

## Related controls

CIS v5.0.0 3.6 / Security Hub KMS.4 (rotation). SOC 2: CC6.1, CC6.7.
