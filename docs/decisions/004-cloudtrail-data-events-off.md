# ADR-004: CloudTrail data events off; GuardDuty S3 Protection on

- **Status:** Accepted
- **Date:** 2026-11-15
- **Original question:** Q-d
- **Recommended by:** Not recorded (options presented by Claude)
- **Decided by:** David

## Context

Data events (S3 object reads and writes, Lambda invokes) are billed per event.

## Options considered

1. Data events on.
2. Data events off.

## Decision

Off. Reasoning (David): management events cover the attacks in the threat model. GuardDuty S3 Protection is enabled so that S3 detection does not depend on trail data events.

## Consequences

- Security Hub controls S3.22 and S3.23 (CIS 3.8 and 3.9) fail by design; both are listed in `control-tiers.md`.
- S3 object-level activity is visible only through GuardDuty S3 Protection, not in the trail.

## Related

- [components/guardduty.md](../components/guardduty.md)
- [control-tiers.md](../control-tiers.md)
