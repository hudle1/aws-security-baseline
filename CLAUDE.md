# aws-security-baseline: project rules

## Goal
Terraform baseline for a personal AWS sandbox (AWS CLI profile `sandbox-admin`, region us-east-1).

v1 scope:
- CloudTrail: multi-region, KMS-encrypted, log file validation
- GuardDuty
- Security Hub: AWS Foundational Security Best Practices only; default standards off
- AWS Config: limited resource types, daily recording
- IAM password policy
- Account-level S3 Block Public Access
- AWS Budgets: $10 alarm (actual + forecasted)
- One-command teardown
- Cost note

## Environment
- Windows + PowerShell. Use PowerShell syntax for all commands, scripts, and the Makefile alternative.
- Provide a `make.ps1` if GNU make isn't installed.

## Architecture
Two root modules:
- `infra/guardrails`: free, persistent (budget, password policy, S3 Block Public Access)
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
I write `docs/design-decisions.md` myself. You may add a "Questions for David" section only.

## Repo layout
- `README.md`
- `docs/{architecture,threat-model,design-decisions}.md`
- `infra/{guardrails,baseline}/`
- `tests/` (terraform test)
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
- When there's a design choice, give me the options and trade-offs and let me choose. Record my choice in "Questions for David" so I can write it up in `docs/design-decisions.md`.

## Phase plan
1. Pre-flight + scaffold
2. Architecture + threat model
3. Guardrails stack
4. CloudTrail
5. GuardDuty / Security Hub / Config
6. CI + tests
7. Deploy / verify / screenshots / teardown / README
