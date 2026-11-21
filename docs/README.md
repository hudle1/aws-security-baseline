# Documentation Index

This folder is meant to be enough on its own: someone who has never seen this repo should be able to understand what it builds, why, and how to operate it, using only these docs. Commands are PowerShell (Windows).

**Placeholders:** docs never contain real account IDs, ARNs or email addresses. `<ACCOUNT_ID>` means the sandbox account's 12-digit ID (see `guardrails.tfvars`, which is gitignored).

## Reading order

1. [architecture.md](architecture.md): what is deployed, in which stack, and who writes to what.
2. [threat-model.md](threat-model.md): what we are defending against and what we accept.
3. [control-tiers.md](control-tiers.md): what is in scope now vs later, and which CIS controls fail by design.
4. [compliance-mapping.md](compliance-mapping.md): how each control maps to CIS and SOC 2.
5. [design-decisions.md](design-decisions.md): why we chose what we chose, in David's words. The individual decisions are recorded as [ADRs](decisions/README.md).
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
| [operations/deploy.md](operations/deploy.md) | Prerequisites, access setup including SSO, step-by-step deploy | Written (Phase 7b; `make.ps1` apply targets pending first real run) |
| [operations/teardown.md](operations/teardown.md) | `destroy` vs `destroy-all`, what can block, how to verify | Written (Phase 7b; destroy itself pending, 2026-11-28) |
| [operations/common-changes.md](operations/common-changes.md) | Safe recipes for routine changes | Written (Phase 7b) |
| [operations/troubleshooting.md](operations/troubleshooting.md) | Every real problem hit, with symptom, cause and fix | Started (Phase 3, grows each phase) |
| [operations/runbook-compromised-credentials.md](operations/runbook-compromised-credentials.md) | One-page incident runbook | Written (Phase 7b; not yet rehearsed as a drill) |

## Other

- [decisions/](decisions/README.md): 21 architecture decision records (context, options, decision, consequences, who recommended, who decided) (Phase 7b). ADRs: [001](decisions/001-config-delivers-to-shared-log-bucket.md), [002](decisions/002-separate-kms-keys-per-service.md), [003](decisions/003-no-object-lock-in-v1.md), [004](decisions/004-cloudtrail-data-events-off.md), [005](decisions/005-cloudwatch-logs-and-cis-alarms-later.md), [006](decisions/006-detection-in-us-east-1-only.md), [007](decisions/007-no-forced-password-expiry.md), [008](decisions/008-budget-keeps-credit-refund-filter.md), [009](decisions/009-no-s3-access-logging-on-cloudtrail-bucket.md), [010](decisions/010-log-retention-365-and-30-days.md), [011](decisions/011-account-wide-cloudtrail-log-decrypt.md), [012](decisions/012-real-time-alerts-in-v1.md), [013](decisions/013-config-continuous-recording.md), [014](decisions/014-config-uses-service-linked-role.md), [015](decisions/015-guardduty-s3-protection-only.md), [016](decisions/016-sns-topic-customer-managed-key.md), [017](decisions/017-kms-tamper-rule-matches-any-key.md), [018](decisions/018-free-quick-wins-and-test-finding.md), [019](decisions/019-accept-virtual-root-mfa-for-v1.md), [020](decisions/020-delete-default-vpcs.md), [021](decisions/021-security-hub-fsbp-and-cis-in-scope.md).
- [images/README.md](images/README.md): screenshot list, where to save them and how to redact them.
- [evidence/](evidence/README.md): redacted proof from the live account: `verify.ps1` output, CloudTrail log validation, teardown plan (Phase 7a).
  - [evidence/verify-output.txt](evidence/verify-output.txt): `verify.ps1` output: 35 of 35 controls pass
  - [evidence/validate-logs-output.txt](evidence/validate-logs-output.txt): CloudTrail log file validation, 67/67 digests and 888/888 logs
  - [evidence/block-public-access-demo.md](evidence/block-public-access-demo.md): Account-level Block Public Access denying a public policy
  - [evidence/guardduty-cloudtrail-logging-disabled.md](evidence/guardduty-cloudtrail-logging-disabled.md): The real GuardDuty finding from the `StopLogging` test
  - [evidence/audit-role-read-only.md](evidence/audit-role-read-only.md): Why the Prowler scanner role is read-only
  - [evidence/default-vpc-deletion.md](evidence/default-vpc-deletion.md): Default VPCs deleted in all 17 regions
  - [evidence/teardown-proof.md](evidence/teardown-proof.md): `plan -destroy`: 45 resources and what can block it
- [compliance/prowler-cis-v5.0-summary.md](compliance/prowler-cis-v5.0-summary.md): independent Prowler CIS v5.0 result, compared control by control with Security Hub, account ID redacted (Phase 7a).
- `../CLAUDE.md`: project rules, including the documentation standard and each phase's definition of done.
