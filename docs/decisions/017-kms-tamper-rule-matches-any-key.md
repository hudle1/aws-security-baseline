# ADR-017: The KMS tamper rule matches any key in the account

- **Status:** Accepted
- **Date:** 2026-11-18
- **Original question:** Q-q
- **Recommended by:** Not recorded (options presented by Claude)
- **Decided by:** David

## Context

The rule alerts on `ScheduleKeyDeletion`, `DisableKey` and `PutKeyPolicy`. It must decide which keys count.

## Options considered

1. Our three keys, by ID and ARN.
2. Any KMS key in the account.
3. Key ID only.

## Decision

Option 2: any key in the account. It is never stale, and a new key is covered automatically.

## Consequences

- Trade-off: it also alerts on harmless key work in the sandbox (the alert emails during the Config key policy fix are an example).

## Related

- [components/alerts.md](../components/alerts.md)
