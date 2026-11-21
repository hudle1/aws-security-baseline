# Deploy

How to stand this baseline up in a **personal sandbox AWS account**, from nothing. Commands are PowerShell (Windows 11, Windows PowerShell 5.1). Never use this with an employer's or any production account: it is built for one person, one region and a $10/month budget.

**Verification status:** the plan, check, verify and test targets of `make.ps1` were run against the live account on 2026-11-20 and behave as written here. The `apply-*`, `deploy` and `destroy*` targets of `make.ps1` have **not yet been run end to end** (pending: first full run, at the 2026-11-28 teardown and redeploy). The stacks themselves were deployed in Phases 3 to 5 with the equivalent `terraform` commands that `make.ps1` wraps.

## What you get, and what it costs

Two stacks: `infra/guardrails` (free, persistent) and `infra/baseline` (billed, torn down with one command). Measured so far: **about $0.28 for 20 days** (Cost Explorer, 2026-11-20, including the free trials of Security Hub and GuardDuty). Expected steady state is a few dollars a month; see [README](../../README.md#7-cost) and each component's cost section.

## Prerequisites

1. **An AWS account you own and may experiment in**, with **IAM Identity Center** (SSO) enabled and one user with the `AdministratorAccess` permission set. No IAM users and no long-lived access keys: this repo forbids them.
2. **A budget alarm already in place** (see "The existing budget" below).
3. **Tools** (install any that are missing; after installing, open a new terminal, or reload the PATH with `$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")`):

| Tool | Needed for | Checked with |
| --- | --- | --- |
| Git | the repo | `git --version` |
| AWS CLI v2 | everything | `aws --version` |
| Terraform 1.9 or newer (tested with 1.17.1) | deploy | `terraform version` |
| tflint, checkov, gitleaks (optional) | `.\make.ps1 lint` and the pre-commit hook | `tflint --version`, `checkov --version`, `gitleaks version` |
| pipx and Prowler (optional) | the independent CIS report | `prowler --version` |

Install with `winget` (package names not run in this session; check with `winget search <name>`): `winget install Hashicorp.Terraform`, `winget install Amazon.AWSCLI`, `winget install TerraformLinters.tflint`, `winget install Gitleaks.Gitleaks`. Prowler needs Windows long paths enabled first, see [troubleshooting #21](troubleshooting.md).

## Access setup (SSO)

Create the CLI profile once. The name must be exactly `sandbox-admin`; the scripts and the Terraform provider block rely on it (the provider takes credentials from `AWS_PROFILE`, no profile is written in code).

```powershell
aws configure sso --profile sandbox-admin
```

Answer the prompts: your IAM Identity Center start URL, region `us-east-1`, then choose the sandbox account and the `AdministratorAccess` role. Log in and confirm you are in the right account (every deploy must start with this):

```powershell
aws sso login --profile sandbox-admin
aws sts get-caller-identity --profile sandbox-admin
```

A stale session shows as "token has expired": run `aws sso login --profile sandbox-admin` again (see [troubleshooting #1 and #2](troubleshooting.md)).

For the Prowler scan, create a second permission set with the AWS managed policies `SecurityAudit` and `ViewOnlyAccess`, a profile named `sandbox-audit` for it, and read [evidence/audit-role-read-only.md](../evidence/audit-role-read-only.md). A permission set change reaches the account only after it is re-provisioned in IAM Identity Center.

## The existing budget

The guardrails stack **imports** a budget that must already exist, named `monthly-10-usd` (a $10 monthly cost budget), and manages it from then on. If the account has no such budget, create it first in the console (Billing, Budgets, create a cost budget, monthly, $10, name `monthly-10-usd`) before the first plan. Without it the import will fail (reasoned from the code in `infra/guardrails/main.tf`, not tested on a fresh account).

## Configure the variables

Real values live in gitignored `.tfvars` files; only the `.example` files are committed.

```powershell
Copy-Item infra\guardrails\guardrails.tfvars.example infra\guardrails\guardrails.tfvars
Copy-Item infra\baseline\baseline.tfvars.example infra\baseline\baseline.tfvars
```

| File | Variable | What to put |
| --- | --- | --- |
| both | `account_id` | The 12-digit ID of the sandbox account. Terraform refuses to run in any other account (`allowed_account_ids`), and the scripts compare it with the SSO profile |
| `guardrails.tfvars` | `budget_email` | Address for budget alerts |
| `guardrails.tfvars` | `budget_limit_usd` | Default 10 |
| `guardrails.tfvars` | `security_contact_name`, `_email`, `_phone` | The AWS security contact (Security Hub Account.1). Phone format: digits, spaces, parentheses, plus, hyphen |
| `baseline.tfvars` | `alert_email` | Where real-time security alerts go. Must be a mailbox you watch (see the SNS step) |

Never commit these files. `git status` must not list them; the pre-commit hook and CI (gitleaks) are the second line of defence.

## Deploy

From the repo root, in order. Guardrails first (free), then the baseline.

```powershell
.\make.ps1 check               # the same checks CI runs; must end with no error
.\make.ps1 plan-guardrails     # read-only: read what will change
.\make.ps1 apply-guardrails    # shows the plan again and waits for you to type yes
.\make.ps1 plan-baseline
.\make.ps1 apply-baseline
```

(`.\make.ps1 deploy` runs the two applies and then `verify` in one go.) `make.ps1` never uses `-auto-approve`: each apply prints the plan and waits for `yes`. Read the plan every time; on the first run it creates every resource, on later runs it should show only what you changed.

**The Security Hub wait (about 20 minutes).** Enabling the two standards (FSBP and CIS v5.0.0) makes Security Hub create about a hundred Config rules one by one. In this account it took about 20 minutes to reach `READY`. The stack sets a 40-minute timeout so Terraform waits. If it still times out, do not re-apply: follow [troubleshooting #12](troubleshooting.md). Check progress with:

```powershell
aws securityhub get-enabled-standards --region us-east-1 --profile sandbox-admin --query "StandardsSubscriptions[].StandardsStatus" --output text
```

Both must say `READY`. Security Hub also needs a few more hours before every control has a result; some controls stay `WARNING` (not evaluated) by design.

## Confirm the alert email

Terraform creates the SNS email subscription as **pending**; it cannot confirm it. Within a few minutes of the baseline apply, the `alert_email` mailbox gets "AWS Notification - Subscription Confirmation". **Click Confirm subscription.** Until you do, no alert is delivered. Check:

```powershell
aws sns get-topic-attributes --topic-arn arn:aws:sns:us-east-1:<ACCOUNT_ID>:baseline-security-alerts --region us-east-1 --profile sandbox-admin --query "Attributes.[SubscriptionsConfirmed,SubscriptionsPending]" --output text
```

Expected `1  0`. To prove the whole path once, trigger a harmless test as described in [components/alerts.md](../components/alerts.md) (for example GuardDuty sample findings). All alert emails share one subject, so Gmail groups them into one conversation: expand the thread ([troubleshooting #19](troubleshooting.md)).

## Verify

```powershell
.\make.ps1 verify
```

Runs `scripts\verify.ps1`, a read-only check of 35 controls in the live account. Expected: `35 of 35 passed`, exit code 0. A failing row names the control and the actual value. The reference result is [evidence/verify-output.txt](../evidence/verify-output.txt). For an independent view, run the Prowler scan described in [compliance/prowler-cis-v5.0-summary.md](../compliance/prowler-cis-v5.0-summary.md).

## After deploy: checklist

- [ ] `verify` says 35 of 35.
- [ ] Both Security Hub standards are `READY`.
- [ ] The SNS subscription is confirmed (`1  0`).
- [ ] `git status` is clean and no `.tfvars` or `.tfstate` is tracked.
- [ ] You know how to tear it down: [teardown.md](teardown.md).

## Troubleshooting

[troubleshooting.md](troubleshooting.md) lists every real problem hit while building this, each with symptom, cause and fix.
