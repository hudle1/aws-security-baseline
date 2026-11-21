# ADR-003: No S3 Object Lock on the log bucket in v1

- **Status:** Accepted
- **Date:** 2026-11-15
- **Original question:** Q-c
- **Recommended by:** Not recorded (options presented by Claude)
- **Decided by:** David

## Context

Object Lock can make log objects impossible to delete or overwrite for a retention period.

## Options considered

1. Compliance mode.
2. Governance mode.
3. None for v1.

## Decision

None for v1. Reasoning (David): a compromised admin can bypass governance mode, and compliance mode breaks one-command teardown.

## Consequences

- Tampering is detected, not prevented: CloudTrail log file validation plus bucket versioning (a 30-day undo window).
- A `terraform destroy` erases the audit trail (threat model #12), an accepted sandbox trade-off.
- Roadmap: compliance-mode Object Lock in a separate log-archive account (Tier 2).

## Related

- [threat-model.md](../threat-model.md)
- [control-tiers.md](../control-tiers.md)
- [evidence/validate-logs-output.txt](../evidence/validate-logs-output.txt)
