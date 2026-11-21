# ADR-018: Fix four free failing controls; handle the test finding

- **Status:** Accepted (implemented; see Consequences)
- **Date:** 2026-11-20
- **Original question:** Q-r
- **Recommended by:** Not recorded (options presented by Claude)
- **Decided by:** David

## Context

After Phase 5, Security Hub showed free-to-fix failures, and the GuardDuty test left a real finding.

## Options considered

1. Fix `EC2.7`, `Account.1`, `IAM.18` and `SSM.7` in the guardrails stack as a follow-up PR; leave the rest as documented Tier 1.
2. Leave them all as documented failures.

## Decision

Option 1: quick wins in a follow-up PR. Account contact details live in `guardrails.tfvars` (gitignored), with placeholders in the example file. The test finding was to stay unarchived until the Phase 7 screenshots.

## Consequences

- **Done:** merged as the guardrails quick-wins PRs. Security Hub re-check on 2026-11-20: all four controls PASSED.
- **Changed in Phase 7a:** the finding's evidence was collected and saved (`evidence/guardduty-cloudtrail-logging-disabled.md`) and the finding was archived on 2026-11-20, earlier than planned; archived findings remain visible in the GuardDuty console with the archived filter.
- `docs/operations/deploy.md` was written in Phase 7b.

## Related

- [components/account-quick-wins.md](../components/account-quick-wins.md)
- [evidence/guardduty-cloudtrail-logging-disabled.md](../evidence/guardduty-cloudtrail-logging-disabled.md)
