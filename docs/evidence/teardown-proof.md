# Teardown proof (baseline stack): `terraform plan -destroy`

**Date:** 2026-11-20 (MT) · **Stack:** `infra/baseline` · **Command (read-only, nothing applied):**

```powershell
$env:AWS_PROFILE = 'sandbox-admin'
terraform -chdir=infra/baseline plan -destroy "-var-file=baseline.tfvars" -no-color -input=false -lock=false
```

**Result:** `Plan: 0 to add, 0 to change, 45 to destroy.` Exit code 0, no errors. The real destroy is scheduled for the end of the sprint (2026-11-28), because the follow-on projects depend on this baseline. `guardrails` is not touched by `destroy` (only by `destroy-all`).

## What would be destroyed (45 resources)

| Count | Resource type | Notes |
| ---: | --- | --- |
| 1 | `aws_cloudtrail.main` | Trail stops; logs already delivered stay in the bucket until the bucket is deleted |
| 1 | `aws_s3_bucket.logs` | `force_destroy = true`: contents are deleted with it |
| 6 | `aws_s3_bucket_*` (lifecycle, ownership, policy, public access block, encryption, versioning) | Child settings of the bucket |
| 3 | `aws_kms_key` (cloudtrail, config, alerts) | 7-day deletion window, see below |
| 3 | `aws_kms_alias` | Removed immediately |
| 1 | `aws_config_configuration_recorder` | |
| 1 | `aws_config_configuration_recorder_status` | Stops recording |
| 1 | `aws_config_delivery_channel` | |
| 1 | `aws_iam_service_linked_role.config` | |
| 1 | `aws_guardduty_detector` | Findings history is deleted with it |
| 7 | `aws_guardduty_detector_feature` | |
| 1 | `aws_securityhub_account` | |
| 2 | `aws_securityhub_standards_subscription` (FSBP, CIS v5.0.0) | |
| 1 | `aws_sns_topic` + 1 `aws_sns_topic_policy` + 1 `aws_sns_topic_subscription` | |
| 6 | `aws_cloudwatch_event_rule` + 6 `aws_cloudwatch_event_target` | The six alert rules |
| 1 | `random_id.log_bucket_suffix` | Local only; a new apply generates a new bucket name |

The plan contains no `prevent_destroy`, so nothing in Terraform blocks the destroy by design.

## What could block or surprise the real destroy

| Item | What the plan shows | What happens | Risk |
| --- | --- | --- | --- |
| Log bucket | `force_destroy = true` | Terraform deletes every object, every noncurrent version and every delete marker, then the bucket. Versioned buckets take longer (a few hundred to a few thousand objects here). **The audit trail is erased** (threat model #12, accepted sandbox trade-off) | Low risk of failure; high impact if run by mistake. Mitigation: every destroy shows a plan and needs a typed `yes` |
| KMS keys | `deletion_window_in_days = 7` | Terraform *schedules* deletion; each key sits in `PendingDeletion` for 7 days and can be cancelled in that time (`aws kms cancel-key-deletion`). Aliases are removed at once, so a new apply can reuse the alias names. Any log still encrypted with a deleted key is unreadable (not a problem here: the bucket is deleted with the logs) | Destroy succeeds; the keys linger 7 days. **Pending: whether a key in `PendingDeletion` is billed. Unverified, check the KMS pricing page before relying on "$0 after destroy".** |
| Security Hub / Config ordering | `securityhub_account` depends on `configuration_recorder_status` in code (`securityhub.tf`) | Terraform destroys in reverse: the two standards, then the hub, then Config recorder status, delivery channel and recorder. Do not "help" by stopping Config first: Security Hub controls would lose their data source mid-destroy | Standards subscriptions took more than 10 minutes to create (troubleshooting #12), so destroying them may also be slow. Destroy timeouts are not configured; if one times out, re-run `destroy` |
| Config service-linked role | destroyed after the recorder | Deleting a service-linked role is asynchronous and can fail with a "role is in use" conflict while Config is still shutting down | **Unverified.** If it fails, re-run `destroy`; the role is free either way |
| Bucket policy before bucket | explicit `depends_on` in code | Policy is removed first, then bucket contents, then the bucket | No risk seen |
| GuardDuty | detector features destroyed before the detector | Findings (including archived ones) are deleted with the detector. Evidence files in `docs/evidence/` are the only record afterwards | Low |
| Alert emails during destroy | six rules + targets are destroyed in parallel with the trail and Config | `StopLogging`/`DeleteTrail`/Config recorder calls made by the destroy can trigger alert emails before the rules are gone | Expected noise, not a fault |
| `random_id` | destroyed | The next apply creates a bucket with a different suffix | None |

## After the destroy (to verify, pending until it runs)

- `terraform -chdir=infra/baseline state list` is empty.
- `aws cloudtrail describe-trails` shows no `baseline-trail`; `aws guardduty list-detectors` is empty; `aws securityhub describe-hub` reports not subscribed; `aws configservice describe-configuration-recorders` is empty.
- Three KMS keys show `PendingDeletion` (cancel with `aws kms cancel-key-deletion` inside 7 days if the destroy was a mistake).
- `scripts/verify.ps1` shows the baseline rows failing and the guardrails rows still passing: that is the correct picture of "baseline gone, guardrails kept".
