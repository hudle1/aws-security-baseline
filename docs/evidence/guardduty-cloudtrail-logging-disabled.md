# Evidence: GuardDuty detected the CloudTrail `StopLogging` test

A real (not sample) GuardDuty finding, produced by the alert test in [components/alerts.md](../components/alerts.md): the trail `baseline-trail` was stopped for about 2 seconds and started again. Redacted: account ID, the caller's SSO role and user name, access key ID and source IP are not included.

| Field | Value |
| --- | --- |
| Finding type | `Stealth:IAMUser/CloudTrailLoggingDisabled` |
| Severity | **2.0 (Low)** |
| Title | An AWS CloudTrail trail baseline-trail was disabled. |
| API call | `StopLogging` on `cloudtrail.amazonaws.com` |
| Event time (UTC) | 2026-11-19T06:55:56Z (11:55:56 PM MT, Nov 18) |
| Finding created (UTC) | 2026-11-19T07:18:34Z |
| **Detection delay** | **about 22 minutes after the API call** |
| Finding ID | `fcd0f955f4687a88058c9002db538239` |
| Occurrences (`Service.Count`) | 1 |
| Region | us-east-1 |
| Description | AWS CloudTrail trail baseline-trail was disabled by `<SSO_ROLE>` calling StopLogging under unusual circumstances. This can be attackers attempt to cover their tracks by eliminating any trace of activity performed while they accessed your account. |
| State after this evidence was collected | **Archived** (2026-11-20, with `aws guardduty archive-findings`; reversible with `unarchive-findings`) |

## What it shows

- GuardDuty is a real second detector for a stopped trail, but **slow (about 22 minutes) and rated Low**. The `guardduty-high` alert rule (severity 7 or higher) would not email it. The EventBridge rule `cloudtrail-tamper` is what alerts in about a minute (email at 11:55 PM MT, [alerts.md](../components/alerts.md)). The two are complementary, not interchangeable.
- The finding was triggered by an expected action: the person who made the test call is the account owner. GuardDuty cannot tell a test from an attack, which is why a detective control still needs a human to look.

## How it was collected (read-only, then one write)

```powershell
$det = (aws guardduty list-detectors --profile sandbox-admin --region us-east-1 | ConvertFrom-Json).DetectorIds[0]
# PowerShell 5.1 needs the criteria in a file (troubleshooting #13)
'{"Criterion":{"type":{"Eq":["Stealth:IAMUser/CloudTrailLoggingDisabled"]}}}' | Set-Content -Encoding ascii $env:TEMP\gd-criteria.json
$ids = (aws guardduty list-findings --detector-id $det --finding-criteria "file://$env:TEMP\gd-criteria.json" --profile sandbox-admin --region us-east-1 | ConvertFrom-Json).FindingIds
aws guardduty get-findings --detector-id $det --finding-ids $ids --profile sandbox-admin --region us-east-1      # read
aws guardduty archive-findings --detector-id $det --finding-ids $ids --profile sandbox-admin --region us-east-1  # the only write
```
