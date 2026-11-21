# ADR-012: Real-time alerts on tampering and high-severity findings are in v1

- **Status:** Accepted (implemented and proven in Phase 5)
- **Date:** 2026-11-18
- **Original question:** Q-l
- **Recommended by:** Not recorded (options presented by Claude)
- **Decided by:** David

## Context

The Phase 2 threat model had real-time alerts as Tier 1 (later). Without them, log tampering and key deletion are noticed only when someone looks.

## Options considered

1. Tier 1, later (as in the Phase 2 threat model).
2. v1, built in Phase 5.

## Decision

Option 2: v1. Reasoning (David): it closes the "no real-time alert" gaps for log tampering and key deletion at about $0 cost. Six EventBridge rules publish to one encrypted SNS topic with an email subscription. David also decided (2026-11-18) that threat-model rows #1, #4, #7, #8, #9 and #21 would be updated when Phase 5 shipped.

## Consequences

- **Shipped in Phase 5 and proven end to end:** all six rules were exercised live and all six emails arrived (the four tested last arrived within the same minute as the event, including the `StopLogging` call itself) (see `components/alerts.md`).
- Limits, documented not hidden: us-east-1 only (EventBridge rules are regional); detect-only (a compromised admin can delete the rules or topic; prevention needs SCPs, Tier 2); whether alerts still fire for calls made while the trail is stopped is untested.
- All alerts share one subject, so Gmail groups them into one conversation (troubleshooting #19). A distinct subject per rule is a v1.1 item.

## Related

- [components/alerts.md](../components/alerts.md)
- [operations/troubleshooting.md](../operations/troubleshooting.md)
- [control-tiers.md](../control-tiers.md)
