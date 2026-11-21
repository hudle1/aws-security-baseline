# CI (GitHub Actions)

Every pull request and every push to `main` runs static checks and mock-provider tests on both Terraform stacks. **CI has no AWS credentials.** It cannot read or change the AWS account; it checks the code, not the live account.

Defined in: [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml). Related files: [`.tflint.hcl`](../../.tflint.hcl), [`.github/dependabot.yml`](../../.github/dependabot.yml), [`.github/ci/requirements.txt`](../../.github/ci/requirements.txt), `infra/<stack>/tests/*.tftest.hcl`.

## What runs

| Check name (as shown on the PR) | Command | What it catches | Why we have it |
| --- | --- | --- | --- |
| `fmt` | `terraform fmt -check -recursive` | Inconsistent formatting | Keeps diffs about meaning, not whitespace |
| `validate (guardrails)`, `validate (baseline)` | `terraform init -backend=false -lockfile=readonly`, then `validate` | Syntax errors, wrong argument names, bad references; a provider that does not match the lock file | Cheapest proof the code is loadable |
| `tflint (guardrails)`, `tflint (baseline)` | `tflint` with the Terraform recommended preset and the pinned AWS ruleset | Unused variables, deprecated syntax, AWS-specific mistakes `validate` cannot see | Linter-level quality |
| `checkov` | `checkov -d infra --framework terraform` | Insecure configuration (open buckets, unencrypted resources, wildcard policies) | Security review that never forgets. Fails on any finding; the only way to accept one is an inline `#checkov:skip=<ID>: <reason>` comment |
| `gitleaks` | `gitleaks git` over the full history | Committed secrets, including ones deleted later | Project rule: never commit secrets |
| `test (guardrails)`, `test (baseline)` | `terraform test` (mock AWS provider) | A security setting weakened in code; a validation rule removed | Regression tests for the controls |

## Security properties of the workflow itself

- **No AWS credentials, no secrets** are referenced anywhere. A compromised step still has nothing to steal.
- **`pull_request`, never `pull_request_target`.** `pull_request_target` runs with the base repo's privileges against code from the PR; it is the usual way CI gets compromised.
- **`permissions: contents: read`** at the top of the workflow; every job inherits it.
- **Every action is pinned to a full commit SHA**, with the version in a comment. Tags can be moved; SHAs cannot. Dependabot updates both.
- **gitleaks is installed from its release tarball and checked against a pinned SHA-256**, not through a third-party action.
- **`persist-credentials: false`** on checkout, so the token is not left in `.git/config` for later steps.
- **Job timeouts** (5 to 10 minutes) so a hung job cannot burn minutes.
- **No `paths:` filters and no job-level `if:`.** A *skipped* required check counts as passing, so a path-filtered required check lets an unchecked change merge. (Learned in IAM Policy Guard.) Every job runs every time.
- **`-lockfile=readonly`** on `init`: a provider version cannot change without a reviewed change to `.terraform.lock.hcl`.

## How the tests work

`terraform test` reads `infra/<stack>/tests/*.tftest.hcl`. The tests use `mock_provider "aws"`, so Terraform plans the real code but the AWS provider is replaced by a fake that invents values and never makes an API call.

- **Positive tests** assert a control is on (log bucket versioning `Enabled`, all four Block Public Access flags, log file validation, KMS rotation, password length at least 14, GuardDuty S3 protection, and so on).
- **Negative tests** feed bad input and use `expect_failures` to require that Terraform *refuses* it (malformed `account_id`, malformed `alert_email`, retention under 90 days). If someone loosens the validation, Terraform stops failing and the *test* goes red. They prove the stack fails closed.

What tests cannot prove: that AWS applied the setting. That is checked by `scripts/verify.ps1` and the Prowler report (Phase 7).

Run locally (PowerShell, from the repo root):

```powershell
terraform -chdir=infra/baseline init -backend=false
terraform -chdir=infra/baseline test
terraform -chdir=infra/guardrails init -backend=false
terraform -chdir=infra/guardrails test
```

## How to read a failure

1. Open the PR, scroll to the checks box, click **Details** on the red check.
2. Open the failing step (the red one). The error is at the bottom of its output.

| Red check | Usual meaning | First thing to do |
| --- | --- | --- |
| `fmt` | A file is not formatted | Run `terraform fmt -recursive` locally and commit |
| `validate (...)` | Syntax or reference error, or provider/lock mismatch | Run `terraform -chdir=infra/<stack> validate` locally. For a lock mismatch see troubleshooting #15 |
| `tflint (...)` | A lint rule fired; the output names the rule and line | Fix it, or if intended, add an `ignore` with a reason |
| `checkov` | A security finding; the output names the check ID (`CKV_...`) and resource | Fix the resource. Accepting it needs an inline `#checkov:skip=CKV_...: reason` comment, reviewed in the PR |
| `gitleaks` | A secret-shaped string in the diff or in history | Treat it as a real leak: revoke the credential first, then remove it from history. Do not just delete the line |
| `test (...)` | A control was weakened, or a mock problem | Read the `error_message` of the failed `assert`; it says which control. If the control change was intentional, change the test in the same PR and explain why |

## Required status checks on `main`

Set on 2026-11-20 (branch protection, classic rule). All nine checks in the table above are required, each pinned to the GitHub Actions app so another app cannot satisfy a check by reusing its name, and **strict mode is on** (a branch must be up to date with `main` before merging). Settings that were already there are unchanged: pull request required, 0 approvals, rules apply to admins, no force pushes, no deletions.

Check the live setting (read-only):

```powershell
gh api repos/hudle1/aws-security-baseline/branches/main/protection --jq ".required_status_checks"
```

Rules: no check may have a path filter or an `if:`. A skipped required check counts as passing, and a never-run one blocks the PR forever.

## GitHub-side scanning (outside the workflow file)

Enabled in the repository settings (Security, Advanced Security) and verified through the GitHub API on 2026-11-20:

| Feature | State | Notes |
| --- | --- | --- |
| Secret scanning and push protection | Enabled | A push containing a recognised secret is blocked before it lands |
| Private vulnerability reporting | Enabled | Used by [SECURITY.md](../../SECURITY.md) |
| Dependency graph and Dependabot alerts | Enabled | Alerts on known-vulnerable dependencies |
| Dependabot version updates | Configured in `.github/dependabot.yml` | GitHub Actions, Terraform (both stacks) and the pinned checkov. Dependabot *security updates* are a separate setting and are currently off |
| CodeQL default setup | Configured: language `actions` (the workflow files), default query suite, weekly schedule | First analysis on `main` (2026-11-20): 0 results, 0 open alerts. It is **not** a required check, so it does not gate merges. On PR #11 it appeared as two checks, `Analyze (actions)` and `CodeQL`, both passing; it was **absent from the earlier checks of the same PR** (the first push showed only the nine workflow checks), so do not assume it runs on every commit |

**Not required yet:** making CodeQL a required check is a v1.1 item. When done, add the exact check names (`Analyze (actions)` and `CodeQL` as seen on PR #11; confirm with the API as in the section above) to the required checks, and keep the rule that a required check must have no path filter: a CodeQL run that is skipped counts as passing.

## How to change it safely

- **New check:** add a job with no `paths` or `if`, then add its name to the required checks *after* it has passed once (a required check that has never run blocks every PR).
- **Renaming a job or changing a matrix value** changes the check name. Required checks are matched by name, so update the branch protection in the same change, or merges will wait forever on a check that no longer exists.
- **tflint AWS ruleset version** in `.tflint.hcl` is not updated by Dependabot. Bump it by hand, run `tflint --init` and tflint locally, then commit.
- **Terraform and tflint versions** are pinned in `ci.yml` (`terraform_version`, `tflint_version`). Bump them together with the local install.
- **Never** add `pull_request_target`, AWS credentials, `--soft-fail`, or a baseline file to make a check pass.

## What breaks if it is removed

Nothing in AWS. What is lost: the guarantee that nothing merges to `main` unformatted, unlinted, with an insecure setting, a leaked secret or a weakened control. All of those would depend on one reviewer noticing.

## Cost

$0 in AWS. GitHub Actions minutes: about 9 short jobs per run, a few minutes in total; private repositories on a free plan get 2,000 minutes a month, so this is far below the limit.

## Related controls

CIS AWS Foundations v5.0.0: none directly (these are repository controls). SOC 2: CC8.1 (change management: reviewed, tested changes), CC7.1 (detection of vulnerabilities and misconfigurations before deployment).
