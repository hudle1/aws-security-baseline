# ADR-019: IAM.6: accept virtual root MFA for v1; hardware key is a v1.1 item

- **Status:** Accepted for v1 (revisit with the v1.1 hardware key)
- **Date:** 2026-11-20
- **Original question:** Q-s
- **Recommended by:** Claude (option 1 was already the Tier 1 position in `control-tiers.md`; option 3 was proposed as an extra)
- **Decided by:** David

## Context

Security Hub (CRITICAL) and Prowler (CIS 1.5) fail the control "hardware MFA enabled for the root user". Verified live: root has MFA, it is a virtual (authenticator app) device, and the account has no root access keys.

## Options considered

1. Keep the accepted risk (Tier 1): free; compensating controls are root MFA, no root keys, SSO for daily work and CloudTrail.
2. Register a FIDO2 hardware security key as root MFA (roughly $25 to $55 one time; two keys stored separately is the usual advice).
3. Add a root `ConsoleLogin` alert (EventBridge rule, free) as an extra compensating control with either option.

## Decision

Option 1 for v1. Reasoning (David): root has a virtual MFA and no access keys, it is never used, and daily access is through SSO. "FIDO hardware key for root" is added as a v1.1 item. The root `ConsoleLogin` alert (option 3) was not decided and stays a v1.1 candidate.

## Consequences

- The scorecard keeps one CRITICAL failure (IAM.6 / CIS 1.5) that the README explains.
- "Never used" is David's statement; Prowler 1.6 only confirms no root use in the last day, and CloudTrail records every root sign-in.
- GuardDuty has a root-credential-use finding, but the alert rules do not email it unless it is rated 7 or higher (how it is rated is unverified), so it is not counted as an alert.
- Target date for revisiting: 2027-02-13 (90-day maximum from the risk-acceptance template).

## Related

- [control-tiers.md](../control-tiers.md)
- [compliance/prowler-cis-v5.0-summary.md](../compliance/prowler-cis-v5.0-summary.md)
- [operations/runbook-compromised-credentials.md](../operations/runbook-compromised-credentials.md)
