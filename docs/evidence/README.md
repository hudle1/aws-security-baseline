# Evidence

Proof that what the code asks for is what the live sandbox account actually has. All files are redacted: no account IDs (`<ACCOUNT_ID>`), no emails, no personal details. Commands are PowerShell.

| File | What it proves | How it was produced |
| --- | --- | --- |
| [verify-output.txt](verify-output.txt) | 35 of 35 controls (8 guardrails, 27 baseline) are in the intended state in the live account | `.\scripts\verify.ps1 -OutFile docs\evidence\verify-output.txt` |
| [validate-logs-output.txt](validate-logs-output.txt) | CloudTrail log files were not modified or deleted since the trail was created (67/67 digest files, 888/888 log files valid) | `aws cloudtrail validate-logs` from trail creation to now |
| [block-public-access-demo.md](block-public-access-demo.md) | Account-level Block Public Access rejects a public bucket policy even on a bucket with no protection of its own | Temporary bucket, public-read policy attempt, cleanup |
| [guardduty-cloudtrail-logging-disabled.md](guardduty-cloudtrail-logging-disabled.md) | GuardDuty detected the `StopLogging` test: real finding, severity Low, about 22 minutes later | `aws guardduty get-findings`, then archived |
| [audit-role-read-only.md](audit-role-read-only.md) | The `sandbox-audit` role used by Prowler has only the read-only `SecurityAudit` policy, and a write attempt is denied | `aws iam list-attached-role-policies` plus David's `create-bucket` test |
| [default-vpc-deletion.md](default-vpc-deletion.md) | The default VPC was deleted in all 17 enabled regions after a dry-run, and none remain | `scripts/delete-default-vpcs.ps1` dry-run, then `-Execute`, then a second dry-run |
| [teardown-proof.md](teardown-proof.md) | A destroy of the baseline stack is a clean plan: 45 resources, and what could block it | `terraform plan -destroy` (read-only, not applied) |

## Re-running `verify.ps1`

```powershell
aws sso login --profile sandbox-admin
.\scripts\verify.ps1 -OutFile docs\evidence\verify-output.txt
```

The script is read-only (only `get-`, `describe-` and `list-` calls). It stops if the profile's account differs from `account_id` in `baseline.tfvars`. Exit code 0 means every check passed; 1 means at least one failed or errored. After a baseline `destroy`, the baseline rows are expected to fail (see the end of [teardown-proof.md](teardown-proof.md)).

## What this evidence does not prove

- `verify.ps1` checks the settings listed in its table, not every Security Hub control. The independent view is the Prowler CIS report: [../compliance/prowler-cis-v5.0-summary.md](../compliance/prowler-cis-v5.0-summary.md).
- `validate-logs` covers hours that already have a digest file (digests are hourly), so the newest hour is not included.
