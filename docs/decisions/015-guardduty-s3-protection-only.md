# ADR-015: GuardDuty: S3 Protection only; every other paid plan explicitly disabled

- **Status:** Accepted
- **Date:** 2026-11-18
- **Original question:** Q-o
- **Recommended by:** Not recorded (options presented by Claude)
- **Decided by:** David

## Context

A new GuardDuty detector can switch some paid protection plans on by default.

## Options considered

1. S3 Protection only, every other paid plan explicitly `DISABLED`.
2. Also Lambda protection.
3. Everything on.

## Decision

Option 1. `guardduty-triage` (project P2) will deploy a Lambda: enable Lambda Protection when that Lambda is deployed.

## Consequences

- Security Hub FSBP controls for the disabled plans (GuardDuty.5 to .13) fail by design and are listed in `control-tiers.md`.
- An explicit `DISABLED` stops a billing feature from switching on by accident; the Terraform test asserts it for Runtime Monitoring.
- GuardDuty and Security Hub were still in their 30-day free trial when costs were measured (2026-11-20).

## Related

- [components/guardduty.md](../components/guardduty.md)
- [control-tiers.md](../control-tiers.md)
