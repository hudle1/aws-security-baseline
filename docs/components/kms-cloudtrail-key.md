# Component: CloudTrail KMS key

**Stack:** `infra/baseline` · **Written:** Phase 4 · **Verified live:** 2026-11-18

## What it is

A customer-managed, symmetric AWS KMS key with the alias `alias/baseline-cloudtrail`. CloudTrail uses it to encrypt every log file and digest file it writes to the [log bucket](log-bucket.md). A second, separate key for AWS Config arrives in Phase 5 (decision b).

## Why we have it

Threats in [threat-model.md](../threat-model.md): #3 (a bucket reader also needs `kms:Decrypt`, a second lock), #4 (key deleted or disabled: logs become unreadable), #5 (key policy changed to grant an attacker access or to lock CloudTrail out), #6 (another account's trail using our key). Separate keys per service (decision b) limit the blast radius of one wrong policy.

## Configuration

| Setting | Value | Reason |
| --- | --- | --- |
| `enable_key_rotation` | `true` (365 days) | New key material every year. Old material is kept, so old logs still decrypt. CIS v5.0.0 3.6, Security Hub KMS.4. |
| `deletion_window_in_days` | `7` | The minimum. Deletion is a cancellable pending state, so a mistaken or malicious `ScheduleKeyDeletion` can be reversed (threat model #4). Trade-off: less time to notice. |
| Alias | `alias/baseline-cloudtrail` | Humans, docs and the CLI use the alias. |
| `bypass_policy_lockout_safety_check` | `false` (default) | KMS rejects a policy that would leave nobody able to manage the key. Left on. |

### Key policy statements

| Statement | Allows | Conditions | Threat rows |
| --- | --- | --- | --- |
| `EnableIAMPermissions` | Account root, `kms:*` | None | #5, #4. Lets IAM policies grant access and prevents a lockout. Residual: any IAM admin can use the key. |
| `AllowCloudTrailToEncryptLogsForThisTrail` | `cloudtrail.amazonaws.com`, `kms:GenerateDataKey*` | `aws:SourceArn` = this trail **and** `kms:EncryptionContext:aws:cloudtrail:arn` = this trail | #6, #3. Encrypt side only; cannot read. |
| `AllowCloudTrailToDescribeKey` | `cloudtrail.amazonaws.com`, `kms:DescribeKey` | `aws:SourceArn` = this trail | #4. CloudTrail checks the key when the trail is created or updated. |
| `AllowAccountPrincipalsToDecryptCloudTrailLogs` | Any principal in this account, `kms:Decrypt`, `kms:ReEncryptFrom` | `kms:CallerAccount` = this account **and** encryption context is a trail in this account | #3. |

**Known trade-off (statement 4):** the principal is `*` with an account condition (AWS's documented CloudTrail pattern). It grants decrypt to every principal in the account for CloudTrail-encrypted data, without needing an IAM allow. Fine for a one-admin sandbox. Production: name a dedicated log-reader role.

## File that defines it

`infra/baseline/kms-cloudtrail.tf`: `data.aws_iam_policy_document.cloudtrail_key`, `aws_kms_key.cloudtrail`, `aws_kms_alias.cloudtrail`. Checkov `CKV_AWS_109`, `CKV_AWS_111` and `CKV_AWS_356` are skipped on the policy document, with the reason in the code (the root statement is required to avoid lockout; `*` in a key policy means "this key").

## How to verify it works

Rotation is on:

```powershell
$env:AWS_PROFILE = "sandbox-admin"
$kid = aws kms describe-key --key-id alias/baseline-cloudtrail --region us-east-1 --profile sandbox-admin --query KeyMetadata.KeyId --output text
aws kms get-key-rotation-status --key-id $kid --region us-east-1 --profile sandbox-admin
```

Expected: `KeyRotationEnabled` true, `RotationPeriodInDays` 365.

**Result on 2026-11-18:** exactly that.

The key is enabled and customer-managed:

```powershell
aws kms describe-key --key-id alias/baseline-cloudtrail --region us-east-1 --profile sandbox-admin --query "KeyMetadata.{State:KeyState,Manager:KeyManager,Spec:KeySpec}"
```

Expected: `Enabled`, `CUSTOMER`, `SYMMETRIC_DEFAULT`.

**Result on 2026-11-18:** `State: Enabled`, `Manager: CUSTOMER`, `Spec: SYMMETRIC_DEFAULT` (`Usage: ENCRYPT_DECRYPT`). The 7-day deletion window is set in Terraform (`deletion_window_in_days`); it only applies once deletion is scheduled, so it isn't visible on a live key.

Log objects use this key: see "How to verify" in [log-bucket.md](log-bucket.md).

## How to change it safely

1. Edit the policy in Terraform and read the plan. A policy change applies instantly to a live trail.
2. Never remove `EnableIAMPermissions`. Never remove the two CloudTrail statements while the trail exists: CloudTrail then fails delivery and sets `LatestDeliveryError`.
3. Never delete the key to "clean up". To retire it, first point the trail at a new key, and keep the old key until the last log it encrypted has expired (365 days by default).
4. If the trail is renamed, update `var.trail_name` in the same change: the policy conditions use the trail ARN.

## What breaks if it's removed

New logs can no longer be written (`LatestDeliveryError` appears). Existing logs in the bucket **cannot be decrypted** once the key is gone, which means the audit trail is lost. Security Hub CloudTrail.2 and KMS.4 fail.

## Cost

- **Key:** $1.00/month (prorated hourly).
- **Rotation:** the first and second rotation of a key each add $1.00/month (prorated hourly). The increase is capped at the second rotation; later rotations are not billed. So a key that has rotated twice costs $3.00/month.
- **When it starts:** automatic rotation is every 365 days, and the first is scheduled for one year after creation (`NextRotationDate` in `get-key-rotation-status`). A sandbox that is deployed for demos and destroyed never reaches it.
- **Requests:** negligible, because the bucket key cuts KMS calls.
- **Deletion:** the pricing page does not say whether a key in the 7-day pending-deletion window is billed. **Not verified.**

Source: [AWS KMS pricing](https://aws.amazon.com/kms/pricing/), checked 2026-11-18. Quoted: "For KMS keys that you rotate automatically or on demand, the first and second rotation of the key adds $1/month" and "This price increase is capped at the second rotation, and any subsequent rotations will not be billed."

## Related controls

- Security Hub: CloudTrail.2, KMS.4. KMS.3 flags keys scheduled for deletion.
- CIS v5.0.0: 3.5, 3.6.
- SOC 2: CC6.1, CC6.7 (see [compliance-mapping.md](../compliance-mapping.md)).
