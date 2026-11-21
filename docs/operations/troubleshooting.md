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
10. [Config: `InsufficientDeliveryPolicyException` creating the delivery channel](#10-config-insufficientdeliverypolicyexception-creating-the-delivery-channel)
11. [KMS: `MalformedPolicyDocumentException` "invalid principals" on a key naming a new role](#11-kms-malformedpolicydocumentexception-invalid-principals-on-a-key-naming-a-new-role)
12. [Security Hub: standards subscription times out while `PENDING`, resource left tainted](#12-security-hub-standards-subscription-times-out-while-pending-resource-left-tainted)
13. [PowerShell 5.1: JSON passed to the AWS CLI loses its quotes](#13-powershell-51-json-passed-to-the-aws-cli-loses-its-quotes)
14. [SQS, SNS and IAM reject a placeholder account ID in a policy](#14-sqs-sns-and-iam-reject-a-placeholder-account-id-in-a-policy)

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

## 10. Config: `InsufficientDeliveryPolicyException` creating the delivery channel

**Symptom**

```text
Error: putting ConfigService Delivery Channel (baseline-delivery): ... PutDeliveryChannel ...
InsufficientDeliveryPolicyException: Insufficient delivery policy to s3 bucket: <LOG_BUCKET>,
unable to write to bucket, provided s3 key prefix is 'null', provided kms key is 'arn:aws:kms:us-east-1:<ACCOUNT_ID>:key/<KEY_ID>'.
```

`terraform apply` stops partway: the recorder exists but is not started, and Security Hub is not created (it depends on the recorder status).

**Cause (verified: the apply that applied this fix succeeded on 2026-11-19):** AWS documents that the AWS Config service-linked role has **no KMS permissions**, so when Config is set up with the SLR it delivers to S3 **as the Config service principal** (`config.amazonaws.com`) instead ([Permissions for the KMS Key for the AWS Config Delivery Channel](https://docs.aws.amazon.com/config/latest/developerguide/s3-kms-key-policy.html)). Our Config key policy only allowed the SLR role, so the test write that `PutDeliveryChannel` performs was refused at the key.

How it was found: CloudTrail showed an `sts:AssumeRole` by `config.amazonaws.com` before every failed `PutDeliveryChannel`, no denied KMS or S3 call was logged, and `AWSConfigServiceRolePolicy` contains only read-style KMS actions (`DescribeKey`, `GetKeyPolicy`, ...). The generic error message points at the bucket, which is misleading.

**Wrong first guess (recorded so nobody repeats it):** the bucket policy's extra `aws:SourceArn` condition was removed and the policy rewritten to AWS's three-statement form. The error did not change (it failed again on the second apply), so that was not the cause. `aws:SourceArn` is supported: for the service principal it is always `arn:aws:config:<region>:<ACCOUNT_ID>:*`. It was restored.

**Fix:** in the Config key policy, replace the statement naming the service-linked role with one for `config.amazonaws.com`: `kms:Decrypt` and `kms:GenerateDataKey`, with `aws:SourceAccount` and `aws:SourceArn` conditions. The bucket policy keeps AWS's three statements (`GetBucketAcl`, `ListBucket`, `PutObject` to the Config prefix with `bucket-owner-full-control`), each with `aws:SourceAccount` and `aws:SourceArn`. Then re-plan and apply; a partial apply leaves state consistent, and the saved plan is stale, so delete it and plan again.

**General lesson:** when Config delivery fails with `InsufficientDeliveryPolicyException` and the bucket policy matches AWS's example, check the KMS key policy for the *service principal*, not only the role.

## 11. KMS: `MalformedPolicyDocumentException` "invalid principals" on a key naming a new role

**Symptom**

```text
MalformedPolicyDocumentException: Policy contains a statement with one or more invalid principals.
```

on `CreateKey` for the Config key, a few seconds after the service-linked role was created.

**Cause:** the key policy names the new AWS Config service-linked role. IAM changes are eventually consistent, so for a few seconds KMS does not yet see the role and treats the principal as invalid.

**Fix:** none needed. The AWS provider retries `CreateKey` for this error and succeeded within about 15 seconds (2026-11-18). The explicit `aws_iam_service_linked_role` resource, referenced by the key policy, guarantees the role is created first. If you ever see it fail outright, re-run `terraform apply`.

## 12. Security Hub: standards subscription times out while `PENDING`, resource left tainted

**Symptom**

```text
Error: waiting for Security Hub Standards Subscription (arn:aws:securityhub:us-east-1:<ACCOUNT_ID>:subscription/aws-foundational-security-best-practices/v/1.0.0) create:
timeout while waiting for state to become 'READY, INCOMPLETE' (last state: 'PENDING', timeout: 3m0s)
```

for both FSBP and CIS. `terraform state show` marks them `(tainted)`.

**Cause:** enabling a standard makes Security Hub create about a hundred AWS Config rules one at a time. In this account it took about **20 minutes** to reach `READY` (2026-11-19). The AWS provider's default wait is 3 minutes, so it gives up and marks the resource tainted. AWS was fine; Terraform was impatient. A tainted resource would be destroyed and recreated on the next apply, which means disabling and re-enabling the standard.

**Fix:**

1. Do **not** re-apply yet. Wait until both standards are `READY`:

```powershell
aws securityhub get-enabled-standards --region us-east-1 --profile sandbox-admin --query "StandardsSubscriptions[].StandardsStatus" --output text
```

2. Tell Terraform the resources are fine (this edits only the local state file, not AWS), then confirm the plan is empty:

```powershell
terraform untaint aws_securityhub_standards_subscription.fsbp
terraform untaint aws_securityhub_standards_subscription.cis
terraform plan "-var-file=baseline.tfvars" -detailed-exitcode
```

Exit code 0 means no changes.

**Prevention:** `securityhub.tf` now sets `timeouts { create = "40m" }` on both subscriptions. A fresh deploy should wait instead of failing (pending verification on the next fresh deploy).

## 13. PowerShell 5.1: JSON passed to the AWS CLI loses its quotes

**Symptom:** `aws sns set-topic-attributes ... --attribute-value '{...json...}'` fails with `Invalid parameter: Policy Error: null`, or a JSON filter such as `--finding-criteria '{...}'` is rejected as malformed, even though the JSON looks right.

**Cause:** Windows PowerShell 5.1 passes arguments to native programs through the command line and strips the double quotes inside the JSON.

**Fix:** write the JSON to a file with no BOM and pass it as `file://`. The AWS CLI accepts `file://` for any parameter that takes a string:

```powershell
[IO.File]::WriteAllText($f, $json, (New-Object Text.UTF8Encoding($false)))
aws sns set-topic-attributes --topic-arn <TOPIC_ARN> --attribute-name Policy --attribute-value ("file://" + ($f -replace '\','/'))
```

Where a command takes inline JSON and a file is awkward, escape each inner quote as `\"` (the single-quoted form with `\"` worked for `--filters` and `--finding-criteria`). Never leave test files containing real values behind; delete them after use.

## 14. SQS, SNS and IAM reject a placeholder account ID in a policy

**Symptom**

```text
SQS: InvalidAttributeValue: Invalid value for the parameter Policy.
SNS: InvalidParameter: Invalid parameter: Policy Error: PrincipalNotFound
IAM: MalformedPolicyDocument: Invalid principal in policy: "AWS":"arn:aws:iam::111122223333:root"
```

while trying to create a test resource shared with the AWS documentation example account `111122223333` (to trigger an IAM Access Analyzer finding).

**Cause:** these services check that the account named as a principal exists. A documentation placeholder is not a real account.

**Fix:** use a principal that is valid without being a real second account. The test that worked used an IAM role whose trust policy names `"AWS": "*"` limited by a random `sts:ExternalId` condition, with **no permission policies**, deleted about 90 seconds later (Access Analyzer raised the finding in 74 seconds). Role name `aa-alert-test-delete-me`. After the role was deleted, Access Analyzer set the finding to `RESOLVED` on its own (this overrides a manual archive), so no manual clean-up of the finding is needed. Or use a real account ID you own.

## 15. CI: `terraform validate` / `test` fail with "cached package ... does not match any of the checksums"

**Symptom** (GitHub Actions, Linux runner; the same code passes on the Windows laptop)

```text
Error: missing or corrupted provider plugins:
  - registry.terraform.io/hashicorp/aws: the cached package for registry.terraform.io/hashicorp/aws 6.73.0 (in .terraform/providers) does not match any of the checksums recorded in the dependency lock file
```

**Cause:** `.terraform.lock.hcl` was created by `terraform init` on Windows, so it recorded only the Windows (`windows_amd64`) package hash. The Linux runner downloads a different package for the same version and finds no matching hash. The CI uses `-lockfile=readonly`, so Terraform refuses to add one silently (which is the point of that flag).

**Fix:** add the hashes for every platform that runs this code, in each stack, and commit the lock files:

```powershell
terraform -chdir=infra/guardrails providers lock -platform=windows_amd64 -platform=linux_amd64 -platform=darwin_amd64 -platform=darwin_arm64
terraform -chdir=infra/baseline providers lock -platform=windows_amd64 -platform=linux_amd64 -platform=darwin_amd64 -platform=darwin_arm64
```

The diff only adds `h1:`/`zh:` lines; provider versions do not change.

## 16. `terraform test`: "Invalid testing directory" when tests live in the repo-root `tests/`

**Symptom**

```text
Error: Invalid testing directory
The testing directory must be a relative path pointing to a directory local to the configuration directory.
```

after `terraform -chdir=infra/baseline test -test-directory=../../tests/baseline`.

**Cause:** Terraform only runs tests found inside the module's own directory.

**Fix:** keep tests in `infra/<stack>/tests/` (Terraform's default location) and run `terraform -chdir=infra/<stack> test`. The repo-level `tests/` folder from the original layout is not used.

## 17. `terraform test` with a mock provider: plan fails before any assert runs

Four separate errors, all because a mock invents a random value for every attribute the real provider would compute, and the provider schema still validates those values.

| Symptom | Cause | Fix |
| --- | --- | --- |
| `"policy" contains an invalid JSON: invalid character 'd' looking for beginning of value` (on a KMS key, bucket policy, SNS policy) | The mocked `aws_iam_policy_document.json` is a random string, and `policy` arguments must be JSON | In `mock_provider "aws"` add `mock_data "aws_iam_policy_document"` with `defaults = { json = "{...valid JSON...}" }` |
| `"standards_arn" (arn:aws:securityhub:3ni6ms9r::...) is an invalid ARN: invalid region value` | The mocked `aws_region` returns a random region and ARNs are built from it | `mock_data "aws_region"` with `name` and `region` set to `us-east-1` |
| `"kms_key_id" (20m66g92) is an invalid ARN: arn: invalid prefix` (also `role_arn`, `topic_arn`) | After an `apply` run, mocked resources return random `arn` values that other resources validate | `mock_resource` defaults with a well-formed `arn` for `aws_kms_key`, `aws_sns_topic`, `aws_iam_service_linked_role` |
| `Invalid import request: Cannot import resources from mock providers` | The guardrails stack has an `import` block for the budget, and a mock cannot import | `override_resource { target = aws_budgets_budget.monthly }` at the top of the test file |

Also: asserting on an attribute that is only known after apply (the trail's `kms_key_id`) fails with "Unknown condition value" in a `plan` run. That one assertion uses `command = apply`, which is safe with a mock provider because the real AWS provider is never loaded.

## 18. PowerShell 5.1: `--filters` JSON for `aws securityhub get-findings` fails with "Invalid JSON"

Same cause and general fix as #13 (quotes stripped from inline JSON). Write the filter to a file and pass `--filters "file://<path>"`. Exact command: see [account-quick-wins.md](../components/account-quick-wins.md).

## 19. Security alert emails "did not arrive" (they were grouped into an old Gmail conversation)

**Symptom:** three alert tests (GuardDuty sample, CloudTrail stop/start, Config stop/start) looked like they sent no email; a Gmail search for new alerts showed only the Access Analyzer one.

**Cause:** nothing was lost. Every alert has the same subject, so Gmail files each new one into the existing conversation with the earlier alerts. The conversation list shows only the latest message's time and preview, and a date-restricted search used the wrong date. Checked first on the AWS side: all six rules matched once with no failed invocations, SNS published and delivered the same number of messages with none failed, and the subscription was confirmed.

**Fix / how to verify:** expand the conversation and read the individual messages, or search `"SECURITY ALERT"` with a date range wide enough to include the test (Gmail's `after:` uses the account's time zone). To prove the AWS side without trusting the inbox:

```powershell
aws cloudwatch get-metric-statistics --region us-east-1 --profile sandbox-admin --namespace AWS/SNS --metric-name NumberOfNotificationsDelivered --dimensions Name=TopicName,Value=baseline-security-alerts --start-time <UTC_START> --end-time <UTC_END> --period 300 --statistics Sum
```

(`NumberOfNotificationsFailed` should have no datapoints.) The real fix is a distinct subject per rule: v1.1 item in [control-tiers.md](../control-tiers.md). Until then, a real incident email can be missed if the conversation is muted, filtered or not opened.

