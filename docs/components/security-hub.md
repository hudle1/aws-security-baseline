# Component: Security Hub

**Stack:** `infra/baseline` · **Written:** Phase 5 · **Verified live:** 2026-11-19

## What it is

AWS Security Hub (now branded "Security Hub CSPM" in the console and in API errors; the Terraform resources are still `aws_securityhub_*`) with **default standards off** and exactly two standards enabled explicitly:

- AWS Foundational Security Best Practices v1.0.0 (FSBP)
- CIS AWS Foundations Benchmark **v5.0.0**, the latest version Security Hub offers (`describe-standards`, 2026-11-19). It contains **40 controls** in Security Hub.

Findings use `SECURITY_CONTROL` consolidation: one finding per control even when a control appears in both standards.

## Why we have it

It is the scorecard: it turns Config data into pass/fail checks against recognised benchmarks. Threat model #9 (standards disabled) and the evidence for #7. It does not alert by itself in v1.

## Configuration

| Setting | Value | Reason |
| --- | --- | --- |
| `enable_default_standards` | `false` | The default would also switch on the old CIS v1.2.0. We choose the two standards ourselves. |
| `control_finding_generator` | `SECURITY_CONTROL` | One finding per control, less noise. |
| `auto_enable_controls` | `true` | New controls in an enabled standard turn on automatically. |
| Standards | FSBP v1.0.0, CIS v5.0.0 | CLAUDE.md scope. |
| Dependency | the Config recorder status | Every check is an AWS Config rule. |
| Subscription `timeouts.create` | `40m` | Enabling a standard takes about 20 minutes (see below). |

## File that defines it

`infra/baseline/securityhub.tf`.

## How to verify it works

```powershell
aws securityhub get-enabled-standards --region us-east-1 --profile sandbox-admin --query "StandardsSubscriptions[].[StandardsArn,StandardsStatus]" --output text
aws securityhub describe-hub --region us-east-1 --profile sandbox-admin --query "{AutoEnable:AutoEnableControls,Gen:ControlFindingGenerator}"
```

**Result on 2026-11-19:** both standards `READY`, `AutoEnable` true, `SECURITY_CONTROL`.

**Enabling takes about 20 minutes.** After the account was created the standards stayed `PENDING` while Security Hub created its Config rules one by one, then became `READY`. The AWS provider's 3-minute default timed out and left the subscriptions *tainted* (troubleshooting #12). Do not re-apply while `PENDING`: wait for `READY`, then `terraform untaint` if needed.

### First scorecard (2026-11-19, a few minutes after READY)

| Result | Count |
| --- | --- |
| Passed | 112 |
| Failed | 31 (listed in [control-tiers.md](../control-tiers.md)) |
| Warning (cannot evaluate: `CONFIG_RECORDER_MISSING_REQUIRED_RESOURCE_TYPES`) | 267 |

Counts will change as Config rules finish evaluating. The 267 are the consequence of recording only seven resource types ([config.md](config.md)).

## How to change it safely

1. Adding a standard enables many Config rules and costs per check: record the decision first.
2. A subscription that is `PENDING` or tainted must not be re-applied; check `get-enabled-standards`.
3. Disabling a control (instead of fixing it) hides it from the score; do that only as a documented risk acceptance in `control-tiers.md`.

## What breaks if it's removed

The scorecard and all control findings disappear. Nothing else in the baseline stops working.

## Cost

30-day free trial, then about $0.0010 per security check per account per region, plus the Config rule evaluations it triggers. With about 150 evaluated controls and few changes this is cents to a few dollars per month. **Estimate, to verify in Cost Explorer.**

## Related controls

Security Hub is the CIS/FSBP scorecard itself. SOC 2: CC7.1, CC7.2.
