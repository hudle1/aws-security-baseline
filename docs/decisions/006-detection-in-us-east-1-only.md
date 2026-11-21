# ADR-006: GuardDuty, Config and Security Hub in us-east-1 only

- **Status:** Accepted
- **Date:** 2026-11-18
- **Original question:** Q-f
- **Recommended by:** Not recorded (options presented by Claude)
- **Decided by:** David

## Context

CloudTrail is multi-region, but GuardDuty, Config and Security Hub are regional. An attacker acting in another enabled region is logged but not detected (threat model #10).

## Options considered

1. GuardDuty in all 17 enabled regions (near $0 when idle, more resources to manage and tear down).
2. us-east-1 only, documented residual risk.
3. Opt out of unused opt-in regions (the 17 default regions cannot be disabled without Organizations SCPs).

## Decision

Option 2: us-east-1 only for v1. Decided by David on 2026-11-18.

## Consequences

- Compensating controls: the multi-region trail (evidence in every region) and the gross-spend budget alarm (catches cost spikes such as crypto-mining in any region).
- Roadmap: the first v1.1 item is GuardDuty in all enabled regions with cross-region alert forwarding to us-east-1. Production fix: an SCP denying unused regions.
- Prowler and `verify.ps1` were run for us-east-1 only; CIS requirements that apply per region are evaluated for that region.

## Related

- [threat-model.md](../threat-model.md)
- [components/guardduty.md](../components/guardduty.md)
