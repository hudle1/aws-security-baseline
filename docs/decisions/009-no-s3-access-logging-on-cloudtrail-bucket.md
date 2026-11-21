# ADR-009: No S3 server access logging on the CloudTrail bucket (CloudTrail.7): Tier 1 exception

- **Status:** Accepted
- **Date:** 2026-11-18
- **Original question:** Q-i
- **Recommended by:** Not recorded (options presented by Claude)
- **Decided by:** David

## Context

CIS v5.0.0 3.4 (Security Hub `CloudTrail.7`) requires server access logging on the CloudTrail bucket. An earlier note wrongly said the control was in neither standard (corrected 2026-11-19): it is in CIS v5.0.0 and it fails.

## Options considered

1. Tier 1 exception, no second bucket.
2. In scope: a second hardened access-log bucket plus logging on the log bucket.

## Decision

Option 1: Tier 1 exception. Reasoning: a second bucket would itself need Block Public Access, versioning and a policy, and Checkov would then flag that bucket for having no logging, which is a loop.

## Consequences

- Checked live on 2026-11-20: `CloudTrail.7` belongs to exactly one enabled standard, CIS AWS Foundations v5.0.0 (requirement 3.4), with severity LOW and status FAILED. It is not part of FSBP. The earlier claim "in neither standard" was wrong, and a code comment and one component doc repeated it until 2026-11-20, when both were corrected.
- `CKV_AWS_18` is skipped in code with this reason. CloudTrail.7 and Prowler 3.4 both FAIL (listed in `control-tiers.md`).
- Bucket-level actions are still CloudTrail management events; object integrity comes from log file validation.
- `CloudTrail.5` (CloudWatch Logs) is a separate, FSBP-only control that fails because of Q-e.

## Related

- [control-tiers.md](../control-tiers.md)
- [components/log-bucket.md](../components/log-bucket.md)
