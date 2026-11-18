# Component: log-archive bucket

**Stack:** `infra/baseline` · **Written:** Phase 4 · **Verified live:** 2026-11-18

## What it is

One S3 bucket, `aws-security-baseline-logs-<random 8 hex>`, that holds the audit evidence. CloudTrail writes to `AWSLogs/<ACCOUNT_ID>/CloudTrail/` (logs) and `AWSLogs/<ACCOUNT_ID>/CloudTrail-Digest/` (validation digests). AWS Config will use `AWSLogs/<ACCOUNT_ID>/Config/` in Phase 5 (decision a: shared bucket, separate prefixes).

## Why we have it

Threats in [threat-model.md](../threat-model.md): #2 (logs edited or deleted), #3 (bucket made public or read by the wrong principal), #6 (confused deputy: another account's trail writing here), #7 (bucket policy edited), #12 (our own `terraform destroy` erasing the logs), #19 (guardrails destroyed, removing the account-level S3 Block Public Access backstop).

## Configuration

| Setting | Value | Reason |
| --- | --- | --- |
| Name | `aws-security-baseline-logs-` + 8 random hex characters | S3 names are global. A random suffix makes it unique and keeps the account ID out of a name that shows up in logs and screenshots. The suffix never changes (a change would replace the bucket). |
| Object ownership | `BucketOwnerEnforced` | ACLs are off; the bucket policy is the only access control. |
| Block Public Access | all four settings `true` (bucket level) | Same as the account-level setting in guardrails, repeated so the bucket stays protected if the account setting is weakened. |
| Versioning | `Enabled` | Overwritten or deleted files remain as noncurrent versions (threat model #2). Never use `Suspended`: it makes new deletes permanent while looking configured. `mfa_delete` is not set (needs root MFA credentials, not used here). |
| Default encryption | SSE-KMS with the CloudTrail key, bucket key on | Every object is encrypted even if a writer forgets. The bucket key cuts KMS calls. |
| Lifecycle | Current objects expire after `log_retention_days` (365). Noncurrent versions expire after `noncurrent_retention_days` (30). Orphan delete markers are removed. Incomplete multipart uploads abort after 7 days. | See the retention trade-off below. |
| `force_destroy` | `true` | **Sandbox-only trade-off.** Lets `terraform destroy` delete a non-empty bucket. The cost is that one destroy erases the audit trail (threat model #12). Mitigation: every destroy needs a human to approve the plan. Production: `false`, and logs in a separate account. |

**Retention trade-off.** 90 days is cheaper but an intrusion found after 3 months has no evidence. 365 days covers a typical SOC 2 audit window and slow investigations, and costs cents in a one-person sandbox. Digest files expire on the same schedule, so `validate-logs` only works inside the retention window.

### Bucket policy statements

| Statement | Allows / denies | Conditions |
| --- | --- | --- |
| `AWSCloudTrailAclCheck` | `cloudtrail.amazonaws.com` may `s3:GetBucketAcl` | `aws:SourceArn` = this trail, `aws:SourceAccount` = this account |
| `AWSCloudTrailWrite` | `cloudtrail.amazonaws.com` may `s3:PutObject` on `AWSLogs/<ACCOUNT_ID>/CloudTrail/*` and `.../CloudTrail-Digest/*` only | Same two, plus `s3:x-amz-acl` = `bucket-owner-full-control` |
| `DenyInsecureTransport` | **Deny** `s3:*` for everyone | `aws:SecureTransport` = false |

The write statement is **not** `AWSLogs/<ACCOUNT_ID>/*`: that would let CloudTrail write into the Config prefix. The Phase 5 statements for Config go in the clearly marked place at the end of the policy document and must stay on their own prefix.

## File that defines it

`infra/baseline/log-bucket.tf`. Checkov skips, each with a reason in the code: `CKV_AWS_18` (server access logging: Tier 1 exception, not in CIS v5.0.0 or FSBP, see [control-tiers.md](../control-tiers.md)), `CKV_AWS_144` (cross-region replication), `CKV2_AWS_62` (event notifications).

## How to verify it works

```powershell
$env:AWS_PROFILE = "sandbox-admin"
$b = terraform -chdir=infra/baseline output -raw log_bucket_name
aws s3api get-bucket-encryption --bucket $b --profile sandbox-admin --query "ServerSideEncryptionConfiguration.Rules[0].{Algo:ApplyServerSideEncryptionByDefault.SSEAlgorithm,BucketKey:BucketKeyEnabled}"
aws s3api get-bucket-versioning --bucket $b --profile sandbox-admin
aws s3api get-public-access-block --bucket $b --profile sandbox-admin --query PublicAccessBlockConfiguration
aws s3api get-bucket-ownership-controls --bucket $b --profile sandbox-admin --query "OwnershipControls.Rules[0].ObjectOwnership"
```

**Result on 2026-11-18:** `aws:kms` with bucket key `true`; versioning `Enabled`; all four BPA flags `true`; ownership `BucketOwnerEnforced`. The bucket name contained no account ID.

Objects are encrypted with the CloudTrail key (replace the key name with an object key from `aws s3api list-objects-v2 --bucket $b --prefix AWSLogs/`):

```powershell
$arn = aws kms describe-key --key-id alias/baseline-cloudtrail --region us-east-1 --profile sandbox-admin --query KeyMetadata.Arn --output text
aws s3api head-object --bucket $b --key <OBJECT_KEY> --profile sandbox-admin --query "{SSE:ServerSideEncryption,KeyId:SSEKMSKeyId}"
```

**Result on 2026-11-18:** the first event log file (about 15 minutes after the trail was created; 3,621 bytes, under `AWSLogs/<ACCOUNT_ID>/CloudTrail/us-east-1/2026/11/18/`), a digest file, and the two folder markers all showed `aws:kms` and the CloudTrail key ARN. Trail status then showed a `LatestDeliveryTime` and no delivery error.

**Gotcha:** the first objects to appear are zero-byte folder markers (`CloudTrail/`, `CloudTrail-Digest/`), not logs. Filter for `.json.gz` and exclude `CloudTrail-Digest` when waiting for the first event log (see troubleshooting #9).

## How to change it safely

1. Edit `log-bucket.tf` and read the plan. Never apply a bucket policy change you haven't read: a wrong policy stops delivery silently until `LatestDeliveryError` appears.
2. Do not rename the bucket or change `random_id`: that replaces the bucket and, with `force_destroy`, deletes the logs.
3. When adding Config (Phase 5), add statements for its own prefix. Never widen CloudTrail's `PutObject` resource.
4. Lowering `log_retention_days` shortens the `validate-logs` window too. The variable enforces a minimum of 90.

## What breaks if it's removed

CloudTrail delivery fails (`LatestDeliveryError`), and with `force_destroy` every log is deleted with the bucket. Security Hub S3.5 and S3.8 stop reporting. Guardrails (account-level BPA) must never be destroyed to save cost: it is the backstop for this bucket.

## Cost

S3 storage and requests for management events from a one-person sandbox: pennies per month. KMS request cost is small thanks to the bucket key. The key is the main cost, see [kms-cloudtrail-key.md](kms-cloudtrail-key.md).

## Related controls

- Security Hub: S3.1, S3.5, S3.8 (bucket-level BPA and TLS), CloudTrail.2.
- CIS v5.0.0: S3 TLS-only and public-access controls. CloudTrail.7 (server access logging) is not in CIS v5.0.0 and is a documented Tier 1 exception.
- SOC 2: CC6.1, CC6.7 (see [compliance-mapping.md](../compliance-mapping.md)).
