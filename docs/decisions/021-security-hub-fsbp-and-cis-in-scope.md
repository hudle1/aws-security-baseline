# ADR-021: Security Hub enables both FSBP and CIS AWS Foundations v5.0.0

- **Status:** Accepted
- **Date:** 2026-11-15
- **Original question:** scope change, no Q number
- **Recommended by:** Not recorded (options presented by Claude)
- **Decided by:** David

## Context

Security Hub's default standards are off. A portfolio needs a visible posture scorecard and an independent benchmark.

## Options considered

1. FSBP only.
2. FSBP and CIS AWS Foundations Benchmark (latest version Security Hub supports).

## Decision

Both, as an explicit scope change decided by David. The latest supported CIS version was confirmed as **v5.0.0** with `aws securityhub describe-standards` (2026-11-15). Default standards stay off; both are enabled explicitly in Terraform.

## Consequences

- Costs: 30-day free trial, then about $0.0010 per check plus the Config rule evaluations it triggers (estimate, to be confirmed after the trial ends).
- Security Hub's CIS v5.0.0 list has 40 controls (25 passed, 5 failed, 10 not evaluated on 2026-11-20). Prowler gave an independent CIS report, compared in `compliance/prowler-cis-v5.0-summary.md`.

## Related

- [components/security-hub.md](../components/security-hub.md)
- [compliance/prowler-cis-v5.0-summary.md](../compliance/prowler-cis-v5.0-summary.md)
