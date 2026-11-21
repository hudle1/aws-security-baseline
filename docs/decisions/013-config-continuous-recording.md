# ADR-013: AWS Config records continuously

- **Status:** Accepted
- **Date:** 2026-11-18
- **Original question:** Q-m
- **Recommended by:** Not recorded (options presented by Claude)
- **Decided by:** David

## Context

Config can record every change as it happens or take a daily snapshot.

## Options considered

1. Continuous ($0.003 per configuration item, billed only when a resource changes).
2. Daily ($0.012 per item, one item per resource per day).

## Decision

Option 1: continuous. Decided by David on 2026-11-18. Reasoning (David): continuous bills only on change, so in a low-change sandbox it is likely cheaper than daily, and it records a change within minutes instead of up to 24 hours (supports threat model #7). This replaced "daily" in the earlier docs.

## Consequences

- Only 7 resource types are recorded (S3 bucket, KMS key, CloudTrail trail, IAM role, policy, user, group). Security Hub marks the controls for other types as WARNING (not evaluated) and `Config.1` fails.
- Measured cost so far is about $0.06 for the month to date (Cost Explorer, 2026-11-20).

## Related

- [components/config.md](../components/config.md)
- [control-tiers.md](../control-tiers.md)
