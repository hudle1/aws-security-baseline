# ADR-001: AWS Config delivers to the shared log-archive bucket

- **Status:** Accepted
- **Date:** 2026-11-15
- **Original question:** Q-a
- **Recommended by:** Not recorded (options presented by Claude)
- **Decided by:** David

## Context

AWS Config needs an S3 bucket for its snapshots and history. The CloudTrail trail already needs a log bucket.

## Options considered

1. Share the CloudTrail log bucket, with a separate prefix per service.
2. Give Config its own bucket.

## Decision

Option 1: one shared log-archive bucket. Each service is limited to its own prefix (`AWSLogs/<account>/CloudTrail/` and `.../Config/`) with `aws:SourceAccount` / `aws:SourceArn` conditions. Reasoning (David): one hardened log-archive bucket mirrors a real log-archive account and keeps teardown simple.

## Consequences

- One bucket to harden, monitor and destroy.
- The bucket policy has six statements (three per service). A mistake in it can affect both services.
- Each writer must stay inside its prefix; the policy never grants `AWSLogs/<account>/*`.

## Related

- [components/log-bucket.md](../components/log-bucket.md)
- [components/config.md](../components/config.md)
