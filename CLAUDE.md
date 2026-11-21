# aws-security-baseline: project rules

## Goal
Terraform baseline for a personal AWS sandbox (AWS CLI profile `sandbox-admin`, region us-east-1).

v1 scope:
- CloudTrail: multi-region, KMS-encrypted, log file validation
- GuardDuty
- Security Hub: enable BOTH AWS Foundational Security Best Practices AND the CIS AWS Foundations Benchmark (latest version Security Hub supports; verify in Phase 5). Default standards still off; we enable these two explicitly in Terraform.
- AWS Config: limited resource types, continuous recording (decision Q-m)
- IAM password policy
- Account-level S3 Block Public Access
- IAM Access Analyzer (external access analyzer, account zone of trust)
- AWS Budgets: $10 alarm (actual + forecasted)
- Real-time email alerts on tampering and high-severity findings (SNS + EventBridge, built in Phase 5; decision Q-l)
- One-command teardown
- Cost note

## Environment
- Windows + PowerShell. Use PowerShell syntax for all commands, scripts, and the Makefile alternative.
- Provide a `make.ps1` if GNU make isn't installed.

## Architecture
Two root modules:
- `infra/guardrails`: free, persistent (budget, password policy, S3 Block Public Access, IAM Access Analyzer)
- `infra/baseline`: cost-generating (CloudTrail + KMS + bucket, GuardDuty, Security Hub, Config)

Teardown targets:
- `destroy` destroys baseline only
- `destroy-all` destroys both

Budget: an existing manual budget named `monthly-10-usd` ($10 monthly cost) already exists in the sandbox. Do NOT create a second budget. In Phase 3, bring it under Terraform with an `import` block (`aws_budgets_budget`), then add the actual + forecasted notifications.

State: local Terraform state (gitignored). Remote state is documented as a production improvement.

## Security rules
- No long-lived AWS access keys, ever.
- Least privilege.
- No real account IDs, ARNs or emails committed. Use variables + `*.tfvars` (gitignored) with `*.tfvars.example` committed.
- Nothing from my employer.
- CI has no AWS credentials in v1 (static checks only).

## Workflow
- One phase per branch + PR. I review every PR. Never merge yourself.
- Never run `terraform apply` or `terraform destroy` with `-auto-approve`.
- Before any AWS write, show me the plan and wait.

## Docs ownership
I write `docs/design-decisions.md` myself, in my own words. Decisions are recorded as ADRs in `docs/decisions/` (you write and maintain those); present design choices as options and record my choice there.

## Documentation and handover
Requirement: the repo must be handover-ready. If David left the company, someone must be able to understand and operate everything from `docs/` alone.

- `docs/` is the single documentation folder. `docs/README.md` is the index and gives the reading order. Every new doc is linked from it.
- `docs/components/<component>.md`: one per component, written in the phase that builds it. Template:
  1. What it is
  2. Why we have it (the threat it addresses, linked to `threat-model.md`)
  3. Configuration (each setting and its reason)
  4. The file that defines it
  5. How to verify it works (exact PowerShell/CLI commands)
  6. How to change it safely
  7. What breaks if it's removed
  8. Cost
  9. Related CIS / SOC 2 controls
- `docs/operations/`:
  - `deploy.md`: prerequisites, access setup including SSO, step by step
  - `teardown.md`
  - `common-changes.md`
  - `troubleshooting.md`: every real problem we hit and its fix (symptom, cause, fix). Append as problems occur; don't wait for phase end.
  - `runbook-compromised-credentials.md`
- Docs follow the same security rules as code: no real account IDs, ARNs or emails. Use placeholders such as `<ACCOUNT_ID>`.
- Commands in docs are PowerShell and must be exact enough to copy and run. Mark any command or claim not yet verified against the live account as pending, and fix it after verification. Never document something as working that hasn't been run.

## Definition of done (every phase)
A phase is not done until:
- the code is merged-ready, with fmt/validate/tflint/checkov clean (findings fixed, or skipped with a justification comment);
- the component docs for everything the phase builds exist in `docs/components/` and are linked from `docs/README.md`;
- `docs/operations/troubleshooting.md` has an entry for every real problem hit in the phase;
- `docs/operations/` files touched by the phase (deploy, teardown, common-changes) are updated;
- the phase's interview questions have been answered and reviewed.

## Repo layout
- `README.md`
- `docs/` is the single documentation folder (see "Documentation and handover" below):
  - `docs/README.md` (index + reading order)
  - `docs/{architecture,threat-model,design-decisions,control-tiers,compliance-mapping}.md`
  - `docs/components/<component>.md`
  - `docs/operations/{deploy,teardown,common-changes,troubleshooting,runbook-compromised-credentials}.md` (the runbook is one page, written in Phase 7)
  - `docs/compliance/` (Prowler CIS report, account ID redacted)
- Any CIS control that fails by design is listed in `docs/control-tiers.md` and `docs/compliance-mapping.md` with its tier and reason.
- `infra/{guardrails,baseline}/`
- `infra/<stack>/tests/*.tftest.hcl` (terraform test; Terraform only runs tests inside the module, see troubleshooting #16). No repo-root `tests/`.
- `scripts/verify.ps1` (post-deploy API checks = test evidence + demo)
- `.github/workflows/`
- `make.ps1` or `Makefile`
- `SECURITY.md`
- `LICENSE` (MIT)
- No `src/` or `examples/` (pure IaC)

## Teaching mode
- I want to understand everything that's done. Before each change, explain what you're about to do and why, in plain language, including the security reason.
- For every Terraform resource, explain each argument that matters and what would go wrong without it.
- I write some of the code myself: leave `TODO(human)` markers, with hints, for the simpler resources (password policy, S3 Block Public Access, budget import, GuardDuty detector) and review my version. You write the complex pieces (KMS key policy, CloudTrail bucket policy, Config IAM role) and walk me through them line by line.
- Before each `terraform apply`, walk me through the plan output: what's being created, and what each line means.
- At the end of each phase, give me 5 interview-style questions on what we built. I answer, and you tell me what I got wrong.
- When there's a design choice, give me the options and trade-offs and let me choose. Record my choice as an ADR in `docs/decisions/` (with who recommended and who decided). `docs/design-decisions.md` stays in my own words.

## Phase plan
1. Pre-flight + scaffold
2. Architecture + threat model
3. Guardrails stack
4. CloudTrail
5. GuardDuty / Security Hub / Config. Config resource types must include at least `AWS::S3::Bucket`, `AWS::KMS::Key`, `AWS::CloudTrail::Trail` and the IAM types (`AWS::IAM::Role`, `AWS::IAM::Policy`, `AWS::IAM::User`, `AWS::IAM::Group`), because the threat model and David's interview answers depend on Config recording them.

   **Phase 5 also builds real-time alerts** (decision Q-l, moved from Tier 1 into v1; the CloudWatch Logs + CIS metric alarms of decision e stay Tier 1):
   - One SNS topic with an email subscription. The address is a variable in `baseline.tfvars` (gitignored, `sensitive`), with a placeholder in `baseline.tfvars.example`. David confirms the subscription email; Terraform cannot, so the subscription stays pending until he does.
   - EventBridge rules (default bus, us-east-1) that publish to that topic, for:
     - CloudTrail `StopLogging`, `DeleteTrail`, `UpdateTrail`.
     - KMS `ScheduleKeyDeletion`, `DisableKey`, `PutKeyPolicy` on our keys (CloudTrail and Config).
     - S3 `PutBucketPolicy`, `DeleteBucketPolicy`, `PutBucketVersioning` on the log bucket.
     - Config `StopConfigurationRecorder`, `DeleteDeliveryChannel`.
     - GuardDuty findings with severity >= 7.
     - New active IAM Access Analyzer findings.
   - Limits to document, not hide: us-east-1 only (EventBridge rules work only in the region where they are created); the API-call rules depend on the trail running, because EventBridge only receives CloudTrail-sourced events while a trail with logging is on (whether the `StopLogging` call itself is still delivered is verified in Phase 5 by testing, not assumed); a compromised admin can still delete the rules or the topic (detect-only, like everything in v1); GuardDuty and Access Analyzer rules fire only if those services are on.
   - Open items to settle in Phase 5, with the options shown to David: SNS topic encryption (checkov `CKV_AWS_26`; David leans toward a customer-managed key, about $1/month, if EventBridge cannot publish to a topic encrypted with the AWS-managed `aws/sns` key, which is to verify first; the other option is a justified skip); how the KMS rules match our keys (key ID vs alias vs ARN in the event).
   - Nothing alert-related is built before Phase 5.
   - **Phase 5 definition of done, additional items** (on top of "Definition of done (every phase)"):
     - Update threat model rows #1, #4, #7, #8, #9 and #21 so the residual-risk column describes the shipped alerts (and their limits) instead of "Tier 1: EventBridge rule". David decided this happens when Phase 5 ships, not earlier.
     - Each alert rule is tested against the live sandbox and the result is recorded in the component doc (including whether `StopLogging` itself still triggers the alert).
     - The SNS email subscription is confirmed by David, and a test alert has arrived.
6. CI + tests
7. Deploy / verify / screenshots / teardown / README. Run Prowler (installed with pipx) under a read-only SecurityAudit/ViewOnlyAccess SSO profile for an independent CIS report, saved to `docs/compliance/` with the account ID redacted.
