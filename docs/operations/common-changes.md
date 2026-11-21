# Common changes

Recipes for the changes you are most likely to make. Commands are PowerShell, run from the repo root with `aws sso login --profile sandbox-admin` done. Every recipe follows the same loop:

1. **Branch:** `git switch -c <short-name>`. Never change `main` directly (it is protected; CI must pass).
2. **Edit** the file named in the recipe.
3. **Check:** `.\make.ps1 check` (fmt, validate, tests, tflint, checkov: the same as CI).
4. **Read the plan:** `.\make.ps1 plan-guardrails` or `plan-baseline`. It must show only what you meant to change. A surprise "destroy" or "replace" is a stop sign.
5. **PR and merge:** push, open a PR, wait for the 9 required checks (see [ci.md](ci.md)), merge after review.
6. **Apply** from the merged `main`: `.\make.ps1 apply-baseline` (or `apply-guardrails`), read the plan again, type `yes`.
7. **Verify:** `.\make.ps1 verify` (35 of 35) and the component's own verify command.
8. **Docs:** update the component page in `docs/components/`, and add a decision record in `docs/decisions/` if you changed a design choice.

Recipes below that were exercised on the live account say so; the rest are **pending** (written from the code, not yet run).

## Change the alert email address

File: `infra/baseline/baseline.tfvars` (gitignored), variable `alert_email`.

The plan will show the SNS subscription being **replaced**. The new address stays *pending* until its owner clicks the confirmation link; the old address stops receiving alerts as soon as the apply finishes. Confirm and check `SubscriptionsConfirmed = 1` as in [deploy.md](deploy.md). Do the change when you can watch the mailbox, so there is no gap with no one receiving alerts. *(Pending: not run since the first deploy.)*

## Add or change an alert rule

File: `infra/baseline/alerts.tf`, the map `local.alert_rules`. One entry per rule: `description`, an EventBridge `pattern`, `input_paths` and an `input_template`.

- The topic policy lists the rule ARNs automatically (it iterates over the map), so a new rule is allowed to publish without another edit.
- Keep the template to event name, resource name or ID, time, region, severity and the CloudTrail event ID. **Never** add the caller's identity, IP, request parameters or anything that could hold a secret.
- Test with a harmless real call or GuardDuty sample findings, never by disabling a control for more than a few seconds ([components/alerts.md](../components/alerts.md) lists how each rule was tested).
- Remember the limits: us-east-1 only, detect-only, and all rules share one email subject.

## Change log retention

File: `infra/baseline/baseline.tfvars`: `log_retention_days` (default 365, minimum 90) and `noncurrent_retention_days` (default 30, minimum 1). Both are validated, and a Terraform test proves a value below 90 is refused.

Trade-off: shorter is cheaper but an intrusion found late has no evidence; `aws cloudtrail validate-logs` only works inside the retention window because digest files expire on the same schedule ([ADR-010](../decisions/010-log-retention-365-and-30-days.md)). *(Pending: not changed since deploy.)*

## Change the budget limit

File: `infra/guardrails/guardrails.tfvars`: `budget_limit_usd` (must be above 0). Apply the guardrails stack. The budget keeps its "exclude credits and refunds" filter ([ADR-008](../decisions/008-budget-keeps-credit-refund-filter.md)).

## Record more AWS Config resource types

File: `infra/baseline/config.tf`, `recording_group.resource_types`. Today 7 types are recorded: S3 bucket, KMS key, CloudTrail trail and IAM role, policy, user and group. Adding types turns many Security Hub controls from `WARNING` (not evaluated) into real passes or fails, and increases Config cost ($0.003 per configuration item changed, plus rule evaluations). Check the plan and Cost Explorer after a week ([ADR-013](../decisions/013-config-continuous-recording.md)).

## Turn on another GuardDuty protection plan

File: `infra/baseline/guardduty.tf`, `local.guardduty_features`. Change a plan from `"DISABLED"` to `"ENABLED"`. When the guardduty-triage Lambda is deployed, enable `LAMBDA_NETWORK_LOGS` ([ADR-015](../decisions/015-guardduty-s3-protection-only.md)). Every other plan bills per use; check the pricing page first. The Terraform test asserts that `RUNTIME_MONITORING` stays `DISABLED` and `S3_DATA_EVENTS` stays `ENABLED`, so loosening S3 Protection fails CI on purpose.

## Accept or fix a failing control

1. Look the control up in [control-tiers.md](../control-tiers.md). Every known failure has a tier, a reason and a compensating control.
2. To accept it: add the row there, and add an inline skip next to the resource, for example `#checkov:skip=CKV_AWS_18: <reason>`. CI allows in-code skips only (no baseline file, no `--soft-fail`).
3. To fix it: change the code, extend the matching test in `infra/<stack>/tests/`, and re-run `verify`.

## Edit a KMS key policy

Files: `infra/baseline/kms-*.tf`. **High risk:** a wrong key policy can lock everyone out of a key (the "enable IAM permissions" statement is what prevents that), and a service that cannot use its key makes CloudTrail, Config or SNS fail. Change one statement at a time, read the plan, and have the troubleshooting entries open ([#10](troubleshooting.md), [#11](troubleshooting.md)). Any `PutKeyPolicy` triggers the `kms-tamper` alert email: expected.

## Change the trail name

Variable `trail_name` in `infra/baseline/variables.tf` (default `baseline-trail`). The key policy and bucket policy are built from the name, so the plan will show the trail **replaced** and policies updated. Log files already written keep the old name in their path.

## Update providers, Terraform, tflint or checkov

- **Providers and GitHub Actions:** Dependabot opens weekly PRs (github-actions, terraform for both stacks, and the pinned checkov). CI must be green before merge; for a provider update, also run `plan` on both stacks and expect no changes.
- **Lock files** must carry hashes for Windows, Linux and macOS: after any manual provider change run `terraform providers lock -platform=windows_amd64 -platform=linux_amd64 -platform=darwin_amd64 -platform=darwin_arm64` in each stack ([troubleshooting #15](troubleshooting.md)).
- **Terraform and tflint versions** are pinned in `.github/workflows/ci.yml`; the tflint AWS ruleset is pinned in `.tflint.hcl` and is **not** updated by Dependabot. Bump these together with your local install.

## Add a new check or test

Add a job to `ci.yml` with no `paths:` filter and no `if:` (a skipped required check counts as passing), then add its name to the required checks only after it has passed once ([ci.md](ci.md)). Tests go in `infra/<stack>/tests/*.tftest.hcl`; write at least one negative test (`expect_failures`).

## What not to change without a decision record

Anything in a "Decision" line of [docs/decisions/](../decisions/README.md): shared log bucket, separate KMS keys, no Object Lock, data events off, us-east-1 only, retention, the alert design. Write a new ADR that supersedes the old one first.
