# Component: GuardDuty

**Stack:** `infra/baseline` · **Written:** Phase 5 · **Verified live:** 2026-11-19

## What it is

One GuardDuty detector in us-east-1 with findings published every 15 minutes, **S3 Protection on**, and every other paid protection plan explicitly `DISABLED` (decision Q-o). The free foundational sources (CloudTrail management events, VPC flow logs, DNS logs) are always analysed.

| Feature | Status | Why |
| --- | --- | --- |
| `S3_DATA_EVENTS` (S3 Protection) | `ENABLED` | CloudTrail data events are off (decision d), so this is the S3 detection. |
| `EKS_AUDIT_LOGS`, `EKS_RUNTIME_MONITORING`, `RUNTIME_MONITORING`, `EBS_MALWARE_PROTECTION`, `RDS_LOGIN_EVENTS`, `LAMBDA_NETWORK_LOGS` | `DISABLED` | No EKS, EC2/ECS runtime, RDS or Lambda workloads exist to protect; several are billed per vCPU or GB. Explicit so nobody turns on a billing feature by accident. |

**Enable Lambda Protection when P2's Lambda is deployed.** (P2 is `guardduty-triage`, the next sprint project; it deploys a Lambda, and `LAMBDA_NETWORK_LOGS` should move to `ENABLED` in `guardduty.tf` in that change.)

## Why we have it

Managed threat detection without tuning. Threats in [threat-model.md](../threat-model.md): #1 (`Stealth:IAMUser/CloudTrailLoggingDisabled`), #8, #9, and general credential-abuse patterns. High-severity findings (>= 7) are emailed by the `guardduty-high` rule ([alerts.md](alerts.md)).

## Configuration

| Setting | Value | Reason |
| --- | --- | --- |
| `enable` | `true` | Detector on. |
| `finding_publishing_frequency` | `FIFTEEN_MINUTES` | The fastest option (default 6 hours). It controls how soon updated findings reach EventBridge. |
| Features | map in `local.guardduty_features`, one `aws_guardduty_detector_feature` each | Explicit status per plan, including the disabled ones. |
| Region | us-east-1 only | Decision Q-f. All-region GuardDuty with cross-region alert forwarding is the first v1.1 item. |

## File that defines it

`infra/baseline/guardduty.tf`. Checkov `CKV2_AWS_3` (GuardDuty for the org/all regions) is skipped on the detector, citing Q-f.

## How to verify it works

```powershell
$d = aws guardduty list-detectors --region us-east-1 --profile sandbox-admin --query "DetectorIds[0]" --output text
aws guardduty get-detector --detector-id $d --region us-east-1 --profile sandbox-admin --query "{Status:Status,Freq:FindingPublishingFrequency,Features:Features[].[Name,Status]}"
```

**Result on 2026-11-19:** `Status` `ENABLED`, `FIFTEEN_MINUTES`, `S3_DATA_EVENTS` `ENABLED`, `RUNTIME_MONITORING` and `EKS_RUNTIME_MONITORING` `DISABLED`, and the other four paid plans `DISABLED`. Also `AI_PROTECTION` and `AI_ANALYST` `DISABLED` (defaults, not set by us).

Detection end to end: a sample finding (`Backdoor:EC2/C&CActivity.B!DNS`, severity 8) reached the `guardduty-high` rule; a real `StopLogging` produced `Stealth:IAMUser/CloudTrailLoggingDisabled` about **22 minutes later at severity 2.0 (Low)**. A Low finding is below the alert threshold, so GuardDuty alone would not have emailed that event. The EventBridge `cloudtrail-tamper` rule did.

## How to change it safely

1. Enabling a plan is a billing change: check its price and record it in `design-decisions.md` first. Change it only in `local.guardduty_features`.
2. Do not lower the alert threshold below 7 without reading how many findings that creates; Low findings are frequent.
3. Archive sample or test findings after a test; do not delete the detector to clear them.

## What breaks if it's removed

All managed threat detection stops, the `guardduty-high` rule never fires, and Security Hub GuardDuty controls fail. Existing findings are retained for a limited time.

## Cost

30-day free trial on a new detector, then usage-based. For one account with a handful of API calls and no S3 data-event volume, expect cents to a few dollars per month. **Estimate, to verify in the GuardDuty usage page and Cost Explorer.**

## Related controls

- Security Hub FSBP: GuardDuty.1 passes; **GuardDuty.5, .6, .7, .8, .9, .11, .12, .13 fail by design** because the matching plans are off (decision Q-o), see [control-tiers.md](../control-tiers.md). GuardDuty.6 (Lambda Protection) is expected to pass once P2 deploys.
- SOC 2: CC6.8, CC7.2, CC7.3.
