# ADR-008: The imported budget keeps its "exclude credits and refunds" filter

- **Status:** Accepted
- **Date:** 2026-11-16
- **Original question:** Q-h
- **Recommended by:** Not recorded (options presented by Claude)
- **Decided by:** David

## Context

The live budget `monthly-10-usd` excludes `Credit` and `Refund` records, so it measures gross usage. The first Terraform draft had no matching filter, so the first plan would have removed it.

## Options considered

1. Add the matching `filter_expression` so the import changes only the notifications (alerts track gross spend).
2. Accept net-of-credits (simpler code; alerts fire later than real usage when credits exist).

## Decision

Option 1: keep the filter. Reasoning (David): gross spend, so credits cannot mask a compromise-driven cost spike.

## Consequences

- The provider requires `metrics` whenever `filter_expression` is set, so `metrics = ["UnblendedCost"]` (the live value) is also in code.
- `billing_view_arn` is set to the account's `primary` billing view (built from `var.account_id`) so the import does not change it; `plan` stays clean after apply.

## Related

- [components/budget.md](../components/budget.md)
