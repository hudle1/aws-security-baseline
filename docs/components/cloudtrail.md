# Component: CloudTrail trail

**Stack:** `infra/baseline` · **Written:** Phase 4 · **Verified live:** 2026-11-18 (status, settings, first log delivery; `validate-logs` pending)

## What it is

A multi-region AWS CloudTrail trail named `baseline-trail`. It records management events (control-plane API calls such as `CreateUser`, `StopLogging`, `PutBucketPolicy`) from every region, plus global service events (IAM, STS), and delivers them as encrypted, hash-validated files to the [log bucket](log-bucket.md), encrypted with the [CloudTrail KMS key](kms-cloudtrail-key.md).

## Why we have it

Without it, nothing else can be investigated: it is the evidence of who did what. Threats addressed in [threat-model.md](../threat-model.md): #1 (trail stopped or changed), #2 (log files edited or deleted: digest files make that provable), #10 (activity in unmonitored regions: multi-region trail records it). It is a detective control. It does not block anything.

## Configuration

| Setting | Value | Reason |
| --- | --- | --- |
| `name` | `baseline-trail` (variable `trail_name`) | The key policy and bucket policy build the trail ARN from this name, so it is a variable. Renaming replaces the trail **and** changes both policies. |
| `is_multi_region_trail` | `true` | An attacker's activity in another region is still logged. CIS v5.0.0 3.1, Security Hub CloudTrail.1. |
| `include_global_service_events` | `true` | IAM, STS and similar services have no region and log to us-east-1. Without this, IAM changes would be missing. |
| `enable_log_file_validation` | `true` | Hourly signed digest of every log file hash. CIS v5.0.0 3.2, CloudTrail.4. |
| `kms_key_id` | CloudTrail key ARN | SSE-KMS at rest. CIS v5.0.0 3.5, CloudTrail.2. |
| `event_selector` | management events, `read_write_type = "All"` | Decision d: no data events. They cost per event, and GuardDuty S3 Protection covers S3 (Phase 5). |
| CloudWatch Logs / SNS | not configured | Decision e: Tier 1. See [control-tiers.md](../control-tiers.md) (CloudTrail.5 fails by design). |
| `depends_on` bucket policy | yes | CloudTrail refuses to create a trail whose bucket does not yet allow it to write. |

## File that defines it

`infra/baseline/cloudtrail.tf`: `aws_cloudtrail.main`. The trail ARN local is in `infra/baseline/locals.tf`.

## How to verify it works

Set the profile first (`$env:AWS_PROFILE = "sandbox-admin"`).

Trail is logging, with no delivery error:

```powershell
aws cloudtrail get-trail-status --name baseline-trail --region us-east-1 --profile sandbox-admin --query "{IsLogging:IsLogging,LatestDeliveryError:LatestDeliveryError,LatestDeliveryTime:LatestDeliveryTime}"
```

Expected: `IsLogging` true, `LatestDeliveryError` null. `LatestDeliveryTime` stays null until the first log file is delivered (5 to 15 minutes after creation).

**Result on 2026-11-18:** right after apply, `IsLogging` true, no delivery error, `LatestDeliveryTime` null. About 15 minutes later the first event log was delivered: `LatestDeliveryTime` set, still no error.

Trail settings:

```powershell
aws cloudtrail describe-trails --trail-name-list baseline-trail --region us-east-1 --profile sandbox-admin --query "trailList[0].{Multi:IsMultiRegionTrail,Global:IncludeGlobalServiceEvents,Validation:LogFileValidationEnabled}"
```

**Result on 2026-11-18:** all three `true`, and the trail's KMS key matched the `alias/baseline-cloudtrail` key.

Log file integrity (the only thing that actually uses the digest files; nothing runs this automatically). Needs the log bucket and a start time at least an hour old:

```powershell
aws cloudtrail validate-logs --trail-arn <TRAIL_ARN> --start-time 2026-11-18T00:00:00Z --region us-east-1 --profile sandbox-admin
```

**Status: pending.** Not yet run; the first digest arrives about an hour after creation.

## How to change it safely

1. Edit `infra/baseline/cloudtrail.tf`, run `terraform plan "-var-file=baseline.tfvars" "-out=baseline.tfplan"`, and read it.
2. A change to `name` replaces the trail and changes the policies that reference its ARN. Applying a trail rename in two steps can leave a window with no logging; expect a gap.
3. Never turn `enable_logging` off to "fix" something. A stopped trail is the first sign of an attack (GuardDuty `Stealth:IAMUser/CloudTrailLoggingDisabled`).
4. Adding data events or CloudWatch Logs is a cost and design change (decisions d, e): record it in `design-decisions.md` first.

## What breaks if it's removed

Nothing stops working, but the account has no audit trail. Security Hub CloudTrail.1, .2, .4 fail, and an investigation has no evidence. Deleting the trail does not delete logs already in the bucket.

## Cost

The first copy of management events per region is free. The trail itself costs nothing; the key ([kms-cloudtrail-key.md](kms-cloudtrail-key.md)) is the main cost, about $1/month.

## Related controls

- Security Hub: CloudTrail.1, CloudTrail.2, CloudTrail.4. CloudTrail.5 fails by design. CloudTrail.7 is not in CIS v5.0.0 or FSBP.
- CIS v5.0.0: 3.1, 3.2, 3.5.
- SOC 2: CC7.2, CC7.3, CC6.1 (see [compliance-mapping.md](../compliance-mapping.md)).
