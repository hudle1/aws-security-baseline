# Teardown

How to remove what this repo deployed, what is kept, and what can go wrong. The evidence behind the numbers is in [evidence/teardown-proof.md](../evidence/teardown-proof.md) (a read-only `terraform plan -destroy`, nothing applied).

**Schedule:** the real destroy of the baseline stack is planned for **2026-11-28**, the end of the sprint, because the follow-on projects (guardduty-triage and others) depend on this baseline until then.

**Verification status:** the plan below was produced on 2026-11-20 and is accurate for that date. The destroy itself has **not been run** yet. Everything marked *pending* is to be confirmed on 2026-11-28 and this page corrected afterwards.

## Two levels

| Command | Destroys | Keeps | Use when |
| --- | --- | --- | --- |
| `.\make.ps1 destroy` | The **baseline** stack: CloudTrail, the log bucket (and every log), 3 KMS keys, GuardDuty, Security Hub and its standards, Config, the SNS topic and the 6 alert rules (45 resources) | The **guardrails** stack: budget, password policy, account S3 Block Public Access, Access Analyzer, EBS encryption default, security contact, support role, SSM sharing block. All free | Done demoing; stop the billing. **This is the normal teardown** |
| `.\make.ps1 destroy-all` | Both stacks, including the $10 budget. You must type `destroy-all` to continue | Nothing | Retiring the account for good. Think twice: the budget alarm is your cost safety net |

Both always print what will be deleted and wait for you to type `yes`. There is no `-auto-approve` anywhere.

## Before you destroy

The destroy **erases the audit trail** (log bucket with `force_destroy = true`) and GuardDuty's findings. Capture what you want to keep first:

1. Run the evidence again if the account changed since the last run, and commit the output: `.\scripts\verify.ps1 -OutFile docs\evidence\verify-output.txt` and the `validate-logs` command in [evidence/README.md](../evidence/README.md).
2. Take the README screenshots (see the README section "Screenshots"): the Security Hub scorecard and the GuardDuty finding only exist while the stack does.
3. Make sure the other projects that rely on this baseline are finished or know it is going away.
4. Log in and confirm the account: `aws sso login --profile sandbox-admin`, then `aws sts get-caller-identity --profile sandbox-admin`.

## Destroy the baseline

```powershell
.\make.ps1 plan-baseline        # optional: confirm there is no drift first
.\make.ps1 destroy              # prints the 45 resources, waits for yes
```

Expect it to take **10 to 30 minutes**, mostly Security Hub (its standards were slow to create, so they may be slow to delete). If a step times out, run `.\make.ps1 destroy` again; Terraform continues where it stopped.

## What can slow or block it

| Item | What happens | What to do |
| --- | --- | --- |
| **Log bucket** | `force_destroy = true`: Terraform deletes every object, every noncurrent version and every delete marker, then the bucket. A versioned bucket takes longer | Nothing. The logs are gone for good; this is the accepted sandbox trade-off (threat model #12) |
| **KMS keys** | Deletion is *scheduled*, not instant: each of the 3 keys sits in `PendingDeletion` for **7 days** and can be recovered in that time. Aliases are removed at once | To undo within 7 days: `aws kms cancel-key-deletion --key-id <KEY_ID> --profile sandbox-admin`, then re-enable. *Pending:* whether a key in `PendingDeletion` is billed is unverified; check Cost Explorer a week later |
| **Security Hub, then Config (order)** | Terraform destroys the standards, then the hub, then Config's recorder status, delivery channel and recorder. This order is set by `depends_on` in the code | Do not stop Config by hand first: Security Hub's controls would lose their data source mid-destroy |
| **Config service-linked role** | Deleting it is asynchronous and can fail with a "role in use" conflict while Config shuts down (*unverified*) | Wait a few minutes and run `destroy` again. The role is free either way |
| **Alert emails** | The destroy itself calls `StopConfigurationRecorder` and friends, and the six alert rules are removed in parallel, so you may get a few `[SECURITY ALERT]` emails during the destroy | Expected. Ignore them, or check the timestamps match your destroy |
| **State file** | State is local (`infra\baseline\terraform.tfstate`, gitignored). If it is lost, Terraform cannot find the resources | Keep the file until the destroy finishes (remote state is a production improvement) |

## After the destroy: verify

Each command should show the resource is gone (all *pending* until the first real run):

```powershell
terraform -chdir=infra/baseline state list                                      # empty
aws cloudtrail describe-trails --region us-east-1 --profile sandbox-admin       # no baseline-trail
aws guardduty list-detectors --region us-east-1 --profile sandbox-admin         # empty list
aws securityhub describe-hub --region us-east-1 --profile sandbox-admin         # an error: account is not subscribed
aws configservice describe-configuration-recorders --region us-east-1 --profile sandbox-admin   # empty
aws kms list-aliases --region us-east-1 --profile sandbox-admin --query "Aliases[?starts_with(AliasName,'alias/baseline-')]"   # empty
.\scripts\verify.ps1
```

`verify.ps1` should now fail the **baseline** rows and still pass the **guardrails** rows: that is the correct picture of "baseline gone, guardrails kept". After the 7-day window, the 3 keys are deleted.

Cost afterwards: the guardrails stack is free. Check Cost Explorer a few days later to confirm the daily cost is back to $0.00.

## Redeploying

A new `apply-baseline` creates everything again, with a **new log bucket name** (the random suffix is generated fresh). Old logs are not restored. Security Hub's two standards take about 20 minutes to become `READY` again ([deploy.md](deploy.md)), and the alert subscription must be confirmed again (the new subscription is pending).

## Default VPCs (not part of Terraform)

The default VPCs in every enabled region are removed with `scripts\delete-default-vpcs.ps1` (decision [ADR-020](../decisions/020-delete-default-vpcs.md); **status: the dry-run found 17 safe VPCs, deletion pending David's approval**). They are not in Terraform state, so no destroy touches them. To bring one back (free, seconds): `aws ec2 create-default-vpc --region <REGION> --profile sandbox-admin`.
