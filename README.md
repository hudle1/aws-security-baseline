# aws-security-baseline

[![CI](https://github.com/hudle1/aws-security-baseline/actions/workflows/ci.yml/badge.svg)](https://github.com/hudle1/aws-security-baseline/actions/workflows/ci.yml)

Terraform security baseline for a personal AWS account: CloudTrail, GuardDuty, Security Hub (FSBP + CIS v5.0.0), AWS Config, IAM Access Analyzer and free guardrails, with one-command teardown.

**Status:** 🚧 Phase 2 of 7: design docs. Not deployable yet.

## 1. Why this matters
_TODO (Phase 7)._

## 2. Demo
_TODO (Phase 7): Security Hub scorecard screenshot, `verify.ps1` output, Prowler CIS summary._

## 3. Architecture
See [docs/architecture.md](docs/architecture.md): two Terraform stacks (`guardrails`: free and persistent; `baseline`: billed and torn down), data flows, trust boundaries.

## 4. How it works
_TODO (Phase 7): numbered flow._

## 5. Security design
- [Threat model (STRIDE)](docs/threat-model.md)
- [Control tiers](docs/control-tiers.md): Tier 0 / 1 / 2, CIS controls that fail by design, risk-acceptance template
- [Compliance mapping](docs/compliance-mapping.md): CIS AWS Foundations v5.0.0 and SOC 2 CC6–CC8 (maps to, not compliant)
- [Design decisions](docs/design-decisions.md)

## 6. Quick start
_TODO (Phase 7): prerequisites, `make.ps1` deploy, `scripts/verify.ps1`, `make.ps1 destroy` / `destroy-all`._

## 7. Cost
_TODO (Phase 7): expected $/month while deployed, $0 after `destroy`._

## 8. What I'd do in production
_TODO (Phase 7): see the residual-risk column of the [threat model](docs/threat-model.md) and Tier 2 in [control tiers](docs/control-tiers.md)._

## 9. Roadmap
_TODO (Phase 7)._

## 10. Skills demonstrated
_TODO (Phase 7)._

## 11. What I learned
_TODO (Phase 7, written by David)._

## License
[MIT](LICENSE)
