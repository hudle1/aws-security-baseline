# ADR-002: Separate KMS keys for CloudTrail and Config

- **Status:** Accepted
- **Date:** 2026-11-15
- **Original question:** Q-b
- **Recommended by:** Not recorded (options presented by Claude)
- **Decided by:** David

## Context

Both services write encrypted objects to the shared bucket. One customer-managed key could serve both.

## Options considered

1. One customer-managed key for CloudTrail and Config (about $1/month).
2. Separate keys (about $2/month).

## Decision

Option 2: separate keys. Reasoning (David): about $1/month more, but a smaller blast radius if one key policy is wrong, and each policy is simpler to read.

## Consequences

- Three customer-managed keys exist today (CloudTrail, Config, alerts, see Q-p), about $3/month in total.
- CloudTrail encrypts with its key (set on the trail); Config with its own (`s3_kms_key_arn` on the delivery channel). The bucket's default key only applies to writers that name none.
- Each key has its own policy and its own doc under `docs/components/`.

## Related

- [components/kms-cloudtrail-key.md](../components/kms-cloudtrail-key.md)
- [components/kms-config-key.md](../components/kms-config-key.md)
