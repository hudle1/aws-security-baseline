# ADR-007: No forced password expiry (`max_password_age` unset)

- **Status:** Accepted
- **Date:** 2026-11-16
- **Original question:** Q-g
- **Recommended by:** Not recorded (options presented by Claude)
- **Decided by:** David

## Context

Checkov `CKV_AWS_9` wants a maximum password age of 90 days or less.

## Options considered

1. Set 90 days or less (satisfies the Checkov check).
2. Leave unset (passwords never expire).

## Decision

Unset. Reasoning (David, from the code comment): NIST SP 800-63B advises against forced periodic rotation because it pushes users toward weak, predictable passwords; CIS v5.0.0 does not require it; Security Hub IAM.7 passes without it.

## Consequences

- `CKV_AWS_9` is skipped in `main.tf` with this justification (CI requires in-code skips only).
- Length 20 and reuse prevention 24 remain; the account has no IAM users (SSO only), so the policy is a backstop.

## Related

- [components/password-policy.md](../components/password-policy.md)
