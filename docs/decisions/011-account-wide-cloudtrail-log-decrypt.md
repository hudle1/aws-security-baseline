# ADR-011: Who may decrypt CloudTrail logs: the account-wide AWS pattern

- **Status:** Accepted
- **Date:** 2026-11-18
- **Original question:** Q-k
- **Recommended by:** Not recorded (options presented by Claude)
- **Decided by:** David

## Context

Reading a CloudTrail log needs S3 read access and `kms:Decrypt` on the key.

## Options considered

1. AWS's documented pattern: any principal in this account, limited to CloudTrail-encrypted data by encryption context.
2. A named log-reader role only.

## Decision

Option 1: AWS's documented account-wide pattern. Confirmed by David on 2026-11-18. Reasoning (David): S3 read access is still required as a second lock, because reading a log needs both S3 permissions and `kms:Decrypt`.

## Consequences

- Trade-off: the key statement grants decrypt without needing an IAM allow, to every principal in the account.
- Production improvement: a named log-reader role (threat model #3).

## Related

- [components/kms-cloudtrail-key.md](../components/kms-cloudtrail-key.md)
- [threat-model.md](../threat-model.md)
