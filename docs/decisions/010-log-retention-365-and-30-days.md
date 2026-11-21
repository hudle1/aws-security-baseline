# ADR-010: Log retention: 365 days current, 30 days noncurrent versions

- **Status:** Accepted
- **Date:** 2026-11-18
- **Original question:** Q-j
- **Recommended by:** Not recorded (options presented by Claude)
- **Decided by:** David

## Context

Retention decides how long evidence exists and how long log file validation can work.

## Options considered

1. 90 days (cheaper, shorter evidence window).
2. 365 days (covers a typical SOC 2 audit window and slow investigations).

## Decision

365 days for current objects and 30 days for noncurrent versions (variables `log_retention_days`, with a 90-day minimum, and `noncurrent_retention_days`). Confirmed by David on 2026-11-18. Reasoning (David): covers a typical audit window and slow investigations, for pennies.

## Consequences

- Digest files expire on the same schedule, so `aws cloudtrail validate-logs` only works inside that window.
- The 30-day noncurrent window is also the undo window for tampering (threat model #2).

## Related

- [components/log-bucket.md](../components/log-bucket.md)
- [evidence/validate-logs-output.txt](../evidence/validate-logs-output.txt)
