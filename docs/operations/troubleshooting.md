# Troubleshooting

Every real problem hit while building this repo, with symptom, cause and fix. Newest entries at the bottom. Format: **Symptom** (what you see), **Cause**, **Fix**.

## Contents

1. [SSO login fails: profile not found](#1-sso-login-fails-profile-not-found)
2. [Terraform: "No valid credential sources found" / IMDS timeout](#2-terraform-no-valid-credential-sources-found--imds-timeout)
3. [PowerShell: `-var-file=guardrails.tfvars` fails with "Too many command line arguments"](#3-powershell--var-fileguardrailstfvars-fails)
4. [`checkov` command fails: "No module named 'checkov'"](#4-checkov-command-fails-no-module-named-checkov)
5. [`terraform fmt -diff` fails: "diff executable not found"](#5-terraform-fmt--diff-fails-diff-executable-not-found)
6. [`terraform fmt -check` exits with code 3](#6-terraform-fmt--check-exits-with-code-3)
7. [Terraform: "all of `filter_expression,metrics` must be specified"](#7-terraform-all-of-filter_expressionmetrics-must-be-specified)
8. [Checkov still fails a policy after adding `#checkov:skip` on the resource](#8-checkov-still-fails-a-policy-after-adding-checkovskip-on-the-resource)
9. ["First log file" check passes too early (folder markers)](#9-first-log-file-check-passes-too-early-folder-markers)

## 1. SSO login fails: profile not found

**Symptom**

```text
aws: [ERROR]: The config profile (sandbox) could not be found
```

when running `aws sso login --profile sandbox`.

**Cause:** The profile in `~/.aws/config` is named `sandbox-admin`, not `sandbox`. The name must match exactly.

**Fix:** list the real profile names, confirm the profile is an SSO profile, then use the correct name:

```powershell
aws configure list-profiles
aws configure list --profile sandbox-admin
aws sso login --profile sandbox-admin
```

An SSO profile has `sso_session` (or `sso_*`) lines in `~/.aws/config`. If you instead see an access key in `~/.aws/credentials` for it, that is a long-lived key and breaks the project rule of no long-lived AWS access keys.

**Related cleanup:** `iamadmin-general` is an old profile for an account that is no longer accessible. Remove its section from both `~/.aws/config` and `~/.aws/credentials` so no stored keys for it remain. Dead credentials are still credentials. Do not open or paste the contents of the credentials file when doing this.

## 2. Terraform: "No valid credential sources found" / IMDS timeout

**Symptom**

```text
Error: No valid credential sources found
Error: failed to refresh cached credentials, no EC2 IMDS role found ...
dial tcp 169.254.169.254:80: connectex: A socket operation was attempted to an unreachable network.
```

Meanwhile `aws sts get-caller-identity --profile sandbox-admin` works.

**Cause:** The provider block deliberately has no `profile` argument (nothing account-specific is committed). Terraform therefore reads the `AWS_PROFILE` environment variable. `--profile` on the AWS CLI does not set it, and `$env:AWS_PROFILE` only lasts for the current PowerShell session. If it isn't set, the AWS SDK falls back to the EC2 metadata service, which doesn't exist on a laptop; that is the IMDS timeout.

**Fix:** set it in the same terminal (or the same command) that runs Terraform, and refresh the SSO session if it has expired:

```powershell
$env:AWS_PROFILE = "sandbox-admin"
aws sso login --profile sandbox-admin
aws sts get-caller-identity --profile sandbox-admin
```

Note: tools that start a fresh shell per command (including Claude Code) don't keep the variable between commands. Set it in each command that calls Terraform.

## 3. PowerShell: `-var-file=guardrails.tfvars` fails

**Symptom**

```text
Error: Too many command line arguments
Error: Failed to read variables file
Given variables file guardrails does not exist.
```

**Cause:** PowerShell 5.1 splits an unquoted argument like `-var-file=guardrails.tfvars` at the dot. Terraform receives `-var-file=guardrails` and a stray `.tfvars` argument.

**Fix:** quote the whole flag:

```powershell
terraform plan "-var-file=guardrails.tfvars" "-out=guardrails.tfplan"
```

Quote every `-flag=value` argument that contains a dot when calling native programs from PowerShell 5.1.

## 4. `checkov` command fails: "No module named 'checkov'"

**Symptom**

```text
File association not found for extension .py
Traceback (most recent call last):
  File "C:\Users\<you>\.local\bin\checkov.cmd", line 37, in <module>
    from checkov.main import Checkov
ModuleNotFoundError: No module named 'checkov'
```

`pipx list` shows checkov installed.

**Cause (likely):** The pipx-generated `checkov.cmd` shim is not launching the venv's Python, so the module isn't found. `pipx reinstall checkov` did **not** fix it, so this is a shim problem, not a missing package. The exact root cause has not been fully diagnosed.

**Fix (workaround):** call checkov through its own pipx venv interpreter. `-I` runs Python in isolated mode so it doesn't import code from the current directory.

```powershell
$py = "$env:LOCALAPPDATA\pipx\pipx\venvs\checkov\Scripts\python.exe"
& $py -I -m checkov.main -d infra/guardrails --framework terraform --compact --quiet
```

The venv location can be confirmed with `pipx environment --value PIPX_LOCAL_VENVS`. Open item: find a permanent fix for the shim (or run checkov in CI / pre-commit instead).

## 5. `terraform fmt -diff` fails: "diff executable not found"

**Symptom**

```text
Error: Failed to generate diff for main.tf: exec: "diff": executable file not found in %PATH%
```

**Cause:** `terraform fmt -diff` shells out to a Unix `diff` program, which Windows doesn't ship.

**Fix:** don't use `-diff`. Check with `-check`, and if you want to see what changed, compare with git:

```powershell
terraform fmt -check
git diff
```

## 6. `terraform fmt -check` exits with code 3

**Symptom:** `terraform fmt -check` prints a filename and exits 3.

**Cause:** Not an error in the config. Exit 3 means "these files are not canonically formatted". In `main.tf` it was trailing-comment alignment.

**Fix:** run `terraform fmt` (no flags) to rewrite the files, review with `git diff`, and commit. Exit 0 means clean.

## 7. Terraform: "all of `filter_expression,metrics` must be specified"

**Symptom**

```text
Error: Missing required argument
"filter_expression": all of `filter_expression,metrics` must be specified
```

on an `aws_budgets_budget` resource.

**Cause:** The AWS provider treats `filter_expression` and `metrics` as a pair. Setting one without the other fails at `validate`.

**Fix:** set both. When importing an existing budget, copy the live value of `metrics` (for ours, `["UnblendedCost"]`) so the import doesn't change it. Read the live values from the plan output of the first import, or from `aws budgets describe-budget`.

## 8. Checkov still fails a policy after adding `#checkov:skip` on the resource

**Symptom**

```text
Check: CKV_AWS_109: "Ensure IAM policies does not allow permissions management / resource exposure without constraints"
	FAILED for resource: aws_iam_policy_document.cloudtrail_key
```

even though `#checkov:skip=CKV_AWS_109: ...` was written inside `resource "aws_kms_key"`.

**Cause:** Checkov evaluates the `data "aws_iam_policy_document"` block as its own resource. A skip comment only applies to the block it sits in, and the key resource that *uses* the policy is a different block.

**Fix:** put the `#checkov:skip` lines (with the justification) inside the `data "aws_iam_policy_document"` block, and remove them from the key resource. Re-run checkov: 43 passed, 0 failed.

## 9. "First log file" check passes too early (folder markers)

**Symptom:** a script that waits for any object under `AWSLogs/` reports success within a minute of the trail being created, but `get-trail-status` still shows `LatestDeliveryTime: null` and there are no real logs.

**Cause:** CloudTrail first creates zero-byte "folder marker" objects (`.../CloudTrail/` and `.../CloudTrail-Digest/`). A digest file (`CloudTrail-Digest/...json.gz`) can also arrive before the first event log. Neither is the first log file.

**Fix:** look for a `.json.gz` key that does **not** contain `CloudTrail-Digest`:

```powershell
aws s3api list-objects-v2 --bucket <LOG_BUCKET> --prefix "AWSLogs/" --profile sandbox-admin --query "Contents[?ends_with(Key,'.json.gz') && !contains(Key,'CloudTrail-Digest')].Key | [0]" --output text
```

The first event log took about 15 minutes after the trail was created (2026-11-18). `LatestDeliveryTime` in `get-trail-status` becomes non-null at the same time.
