# Documentation Index

This folder is meant to be enough on its own: someone who has never seen this repo should be able to understand what it builds, why, and how to operate it, using only these docs. Commands are PowerShell (Windows).

**Placeholders:** docs never contain real account IDs, ARNs or email addresses. `<ACCOUNT_ID>` means the sandbox account's 12-digit ID (see `guardrails.tfvars`, which is gitignored).

## Reading order

1. [architecture.md](architecture.md): what is deployed, in which stack, and who writes to what.
2. [threat-model.md](threat-model.md): what we are defending against and what we accept.
3. [control-tiers.md](control-tiers.md): what is in scope now vs later, and which CIS controls fail by design.
4. [compliance-mapping.md](compliance-mapping.md): how each control maps to CIS and SOC 2.
5. [design-decisions.md](design-decisions.md): why we chose what we chose.
6. `components/`: one page per component (below). Read the ones you will touch.
7. `operations/`: how to deploy, change, fix and tear down (below).

## Components

Each page covers: what it is, why we have it, configuration, defining file, how to verify, how to change safely, what breaks if removed, cost, and CIS / SOC 2 mapping.

| Component | Stack | Doc | Status |
| --- | --- | --- | --- |
| IAM password policy | guardrails | [components/password-policy.md](components/password-policy.md) | Written (Phase 3) |
| Account-level S3 Block Public Access | guardrails | [components/s3-block-public-access.md](components/s3-block-public-access.md) | Written (Phase 3) |
| IAM Access Analyzer | guardrails | [components/access-analyzer.md](components/access-analyzer.md) | Written (Phase 3) |
| AWS Budget `monthly-10-usd` | guardrails | [components/budget.md](components/budget.md) | Written (Phase 3) |
| CloudTrail trail | baseline | [components/cloudtrail.md](components/cloudtrail.md) | Written (Phase 4) |
| CloudTrail KMS key | baseline | [components/kms-cloudtrail-key.md](components/kms-cloudtrail-key.md) | Written (Phase 4) |
| Log-archive bucket | baseline | [components/log-bucket.md](components/log-bucket.md) | Written (Phase 4) |
| AWS Config | baseline | [components/config.md](components/config.md) | Written (Phase 5) |
| Config KMS key | baseline | [components/kms-config-key.md](components/kms-config-key.md) | Written (Phase 5) |
| GuardDuty | baseline | [components/guardduty.md](components/guardduty.md) | Written (Phase 5) |
| Security Hub | baseline | [components/security-hub.md](components/security-hub.md) | Written (Phase 5) |
| Account quick wins (EBS encryption, security contact, support role, SSM sharing block) | guardrails | [components/account-quick-wins.md](components/account-quick-wins.md) | Written (quick-wins PR, verification pending) |
| Real-time alerts (EventBridge + SNS) | baseline | [components/alerts.md](components/alerts.md) | Written (Phase 5) |
| Alerts KMS key | baseline | [components/kms-alerts-key.md](components/kms-alerts-key.md) | Written (Phase 5) |

## Operations

| Doc | Purpose | Status |
| --- | --- | --- |
| [operations/ci.md](operations/ci.md) | What CI runs, why, how to read a failure, required checks | Written (Phase 6) |
| `operations/deploy.md` | Prerequisites, access setup including SSO, step-by-step deploy | Planned (needed by Phase 7; started as each phase deploys) |
| `operations/teardown.md` | `destroy` vs `destroy-all` and what each deletes | Planned (Phase 7) |
| `operations/common-changes.md` | Safe recipes for routine changes | Planned (grows each phase) |
| [operations/troubleshooting.md](operations/troubleshooting.md) | Every real problem hit, with symptom, cause and fix | Started (Phase 3, grows each phase) |
| `operations/runbook-compromised-credentials.md` | One-page incident runbook | Planned (Phase 7) |

## Other

- [evidence/](evidence/README.md): redacted proof from the live account: `verify.ps1` output, CloudTrail log validation, teardown plan (Phase 7a).
- [compliance/prowler-cis-v5.0-summary.md](compliance/prowler-cis-v5.0-summary.md): independent Prowler CIS v5.0 result, compared control by control with Security Hub, account ID redacted (Phase 7a).
- `../CLAUDE.md`: project rules, including the documentation standard and each phase's definition of done.
