# ADR-005: CloudTrail to CloudWatch Logs and CIS metric alarms: later (Tier 1)

- **Status:** Accepted (premise corrected twice)
- **Date:** 2026-11-15
- **Original question:** Q-e
- **Recommended by:** Not recorded (options presented by Claude)
- **Decided by:** David

## Context

CIS section 4 asks for CloudWatch metric filters and alarms on 15 event types, which needs the trail to send logs to CloudWatch Logs.

## Options considered

1. Build it in v1.
2. Tier 1, later.

## Decision

Tier 1, later. Reasoning (David): cost, and GuardDuty already alerts on root credential use and CloudTrail being stopped. Each affected control is listed in `control-tiers.md` with the reason.

## Consequences

- **Premise corrected twice.** Phase 5 (2026-11-19): Security Hub's CIS v5.0.0 list has 40 controls and none are CloudWatch metric controls, so Security Hub shows no failure from this decision. Phase 7a (2026-11-20): Prowler, which implements the benchmark text, reports CIS 4.1 to 4.15 as **15 failures** caused by this decision.
- `CloudTrail.5` (CloudWatch Logs on the trail) fails; it is an FSBP control, not a CIS v5.0.0 one.
- The EventBridge alerts (Q-l) cover the intent of 4.5, 4.7, 4.9 and, for the log bucket only, 4.8. Not covered: 4.1, 4.2, 4.3, 4.4, 4.6, 4.10 to 4.15.

## Related

- [control-tiers.md](../control-tiers.md)
- [compliance/prowler-cis-v5.0-summary.md](../compliance/prowler-cis-v5.0-summary.md)
