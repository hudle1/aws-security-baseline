# Prowler CIS AWS Foundations v5.0 result, compared with Security Hub

**Scanned:** 2026-11-20 (MT), sandbox account (ID redacted), region `us-east-1` only · **Tool:** Prowler 5.51.0 · **Framework flag:** `--compliance cis_5.0_aws` (found with `prowler aws --list-compliance`) · **Identity:** the read-only `sandbox-audit` SSO profile only (`SecurityAudit` + `ViewOnlyAccess`, see [evidence/audit-role-read-only.md](../evidence/audit-role-read-only.md)); no admin credentials were used.

Prowler exit code 3 means "finished, with FAIL results", not an error. The unredacted raw output (CSV and JSON with account IDs and resource names) was deleted after this summary was written; only this redacted summary is kept.

```powershell
aws sso login --profile sandbox-audit
prowler aws --profile sandbox-audit --compliance cis_5.0_aws -f us-east-1 -o <OUTPUT_DIR> -M csv json-ocsf
prowler aws --profile sandbox-audit --compliance cis_5.0_aws -f us-east-1 --scan-unused-services -o <OUTPUT_DIR> -M csv
```

## Result

| Run | Result rows | PASS | FAIL | MANUAL |
| --- | ---: | ---: | ---: | ---: |
| Default (skips resources that are not in use) | 60 | 37 | 21 | 2 |
| With `--scan-unused-services` | 71 | 43 | 26 | 2 |

Security Hub, same standard (CIS AWS Foundations v5.0.0), same day: **40 controls: 25 PASSED, 5 FAILED, 10 WARNING (not evaluated)**.

The default run produced nothing for EC2, VPC, RDS or EFS: the account has one default security group, **0 network interfaces** and no EBS, RDS or EFS resources, so Prowler counts them as unused and skips them. The second run turns that off so the two tools can be compared on the same ground. **Use the second column as the comparison.** Rows are per resource, so one requirement can have several rows ("FAIL 1 / PASS 13" below is 14 rows for one requirement).

## Control by control

Security Hub numbers the same CIS requirements (the CIS number comes from each finding's `RelatedRequirements`). "no result" means the tool produced no finding for that requirement.

| CIS req | Security Hub control | Security Hub | Prowler (default run) | Prowler (`--scan-unused-services`) |
| --- | --- | --- | --- | --- |
| 1.1 | (none) | - | MANUAL | MANUAL |
| 1.2 | Account.1 | PASSED | MANUAL | MANUAL |
| 1.3 | IAM.4 | PASSED | PASS | PASS |
| 1.4 | IAM.9 | PASSED | PASS | PASS |
| 1.5 | IAM.6 | FAILED | FAIL | FAIL |
| 1.6 | (none) | - | PASS | PASS |
| 1.7 | IAM.15 | PASSED | PASS | PASS |
| 1.8 | IAM.16 | PASSED | PASS | PASS |
| 1.9 | IAM.5 | PASSED | no result | no result |
| 1.10 | (none) | - | PASS | PASS |
| 1.11 | IAM.22 | PASSED | PASS | PASS |
| 1.12 | (none) | - | PASS | PASS |
| 1.13 | IAM.3 | PASSED | PASS | PASS |
| 1.14 | IAM.2 | PASSED | no result | no result |
| 1.15 | (none) | - | FAIL 1 / PASS 13 | FAIL 1 / PASS 13 |
| 1.16 | IAM.18 | PASSED | PASS | PASS |
| 1.18 | IAM.26 | PASSED | no result | no result |
| 1.19 | IAM.28 | PASSED | PASS | PASS |
| 1.20 | (none) | - | PASS | PASS |
| 1.21 | IAM.27 | PASSED | PASS | PASS |
| 2.1.1 | S3.5 | PASSED | PASS | PASS |
| 2.1.2 | S3.20 | PASSED | FAIL | FAIL |
| 2.1.4 | S3.1 + S3.8 | PASSED + PASSED | PASS 2 | PASS 2 |
| 2.2.1 | RDS.3 | WARNING | no result | no result |
| 2.2.2 | RDS.13 | WARNING | no result | no result |
| 2.2.3 | RDS.2 | WARNING | no result | no result |
| 2.2.4.1 | RDS.5 | WARNING | no result | no result |
| 2.2.4.2 | RDS.15 | WARNING | no result | no result |
| 2.3.1.1 | EFS.1 | PASSED | no result | no result |
| 2.3.1.2 | EFS.8 | WARNING | no result | no result |
| 3.1 | CloudTrail.1 | PASSED | PASS | PASS |
| 3.2 | CloudTrail.4 | PASSED | PASS | PASS |
| 3.3 | Config.1 | FAILED | PASS | PASS |
| 3.4 | CloudTrail.7 | FAILED | FAIL | FAIL |
| 3.5 | CloudTrail.2 | PASSED | PASS | PASS |
| 3.6 | KMS.4 | PASSED | PASS 3 | PASS 3 |
| 3.7 | EC2.6 | WARNING | no result | FAIL |
| 3.8 | S3.22 | FAILED | FAIL | FAIL |
| 3.9 | S3.23 | FAILED | FAIL | FAIL |
| 4.1 to 4.15 | (none) | - | FAIL (all 15) | FAIL (all 15) |
| 4.16 | (none) | - | PASS | PASS |
| 5.1.1 | EC2.7 | PASSED | no result | no result |
| 5.2 | EC2.21 | WARNING | no result | FAIL 3 |
| 5.3 | EC2.53 | PASSED | no result | PASS 3 |
| 5.4 | EC2.54 | PASSED | no result | PASS 3 |
| 5.5 | EC2.2 | WARNING | no result | FAIL |
| 5.7 | EC2.8 | WARNING | no result | no result |

## Every difference, explained

Reconciliation of Security Hub's 40 controls: **25 PASSED** = 18 where Prowler also passes + 5 where Prowler has no result + 1 where Prowler says MANUAL + 1 where Prowler FAILS. **5 FAILED** = 4 where Prowler also fails + 1 where Prowler passes. **10 WARNING** = 3 where Prowler (with the flag) finds a real failure + 7 where there is nothing to evaluate.

**1. Both tools agree (22 of 40).** Pass in both (18): IAM.4, IAM.9, IAM.15, IAM.16, IAM.22, IAM.3, IAM.18, IAM.28, IAM.27, S3.5, S3.1, S3.8, CloudTrail.1, CloudTrail.2, CloudTrail.4, KMS.4, EC2.53, EC2.54. Fail in both (4): **IAM.6** (root MFA is virtual, not hardware), **CloudTrail.7** (no access logging on the log bucket), **S3.22** and **S3.23** (no S3 object-level logging). All four are documented in [control-tiers.md](../control-tiers.md). Two of the 18 passes are vacuous in both tools (IAM.22 and IAM.3 pass because there are no IAM users or access keys).

**2. Security Hub PASSED, Prowler FAILS: S3.20 / CIS 2.1.2 (MFA Delete). Prowler is right.** The log bucket has MFA Delete disabled. Security Hub's pass is empty: its reason code is `CONFIG_EVALUATIONS_EMPTY`, meaning the Config rule had nothing to evaluate, and the finding is attached to the account, not to the bucket. This is the most important difference: **a Security Hub "PASSED" can mean "not measured"**. Seven of Security Hub's 25 passes carry that reason (EFS.1, IAM.5, IAM.3, IAM.2, S3.20, IAM.26, IAM.22). Six of them are vacuous because the account has no IAM users or EFS. S3.20 is the only one that hides a real gap. MFA Delete can only be turned on by the root user using root credentials with MFA, and the project forbids root access keys (comment in `log-bucket.tf`), so this is accepted, see [control-tiers.md](../control-tiers.md).

**3. Security Hub FAILED, Prowler PASS: Config.1 / CIS 3.3.** Different definitions, both correct. Security Hub's Config.1 requires recording *all* resource types with the service-linked role and fails because the stack records only 7 types (reason `CONFIG_RECORDER_MISSING_REQUIRED_RESOURCE_TYPES`; decision on cost, [components/config.md](../components/config.md)). Prowler's check only asks whether a recorder is enabled in the scanned region, and our scan covered only `us-east-1`. **Caveat:** CIS 3.3 says "all regions". Other regions were not scanned, and by design (Q-f, us-east-1 only) they have no recorder, so this Prowler PASS must not be read as "Config is in all regions". (Not verified by scanning other regions.)

**4. Security Hub WARNING, Prowler FAILS (3): EC2.6 / 3.7 (VPC flow logs), EC2.21 / 5.2 (network ACLs), EC2.2 / 5.5 (default security group).** Security Hub could not evaluate these (Config does not record those resource types), so it showed WARNING. Prowler, once told to scan unused resources, shows they are real: the default VPC has no flow logs, its default NACL allows all inbound traffic (3 NACL findings), and its default security group allows traffic. Nothing runs in that VPC, so the risk is low, but they are genuine failures hidden by "not evaluated". New entries in [control-tiers.md](../control-tiers.md); fixing them is a choice for David (open question Q-t in design-decisions.md).

**5. Security Hub WARNING, Prowler no result (7): EC2.8 / 5.7 (IMDSv2), RDS.2, .3, .5, .13, .15 (2.2.x), EFS.8 (2.3.1.2).** The account has no EC2 instances, RDS databases or EFS file systems, so there is nothing to evaluate in either tool. Not a gap.

**6. Security Hub PASSED, Prowler no result (5): IAM.5 / 1.9, IAM.2 / 1.14, IAM.26 / 1.18, EFS.1 / 2.3.1.1, EC2.7 / 5.1.1.** For the first four the account has no IAM users, no certificates and no EFS, so both tools have nothing to check (Security Hub reports an empty pass). EC2.7 (EBS default encryption) is a real pass in Security Hub, set by the guardrails stack; **why Prowler returned no result for it is not verified** (a likely cause is that it skips EBS checks when no volumes or snapshots exist, but I did not confirm that).

**7. Security Hub PASSED, Prowler MANUAL: Account.1 / CIS 1.2 (security contact).** Prowler cannot check this itself and asks a human to look in the console. Security Hub checks it automatically; it passes since the guardrails quick-wins PR set the contact ([verify.ps1](../../scripts/verify.ps1) also confirms it). CIS 1.1 (maintain current contact details) is MANUAL in Prowler and has no Security Hub control: a human has to confirm it.

**8. Prowler-only FAIL: 1.15 (full `*:*` administrator policy attached): 1 FAIL of 14 policies.** The AWS managed policy `AdministratorAccess` is attached to exactly one role, the IAM Identity Center administrator role (0 users, 0 groups). That is the SSO admin path itself, not an IAM user with standing admin rights. Security Hub's CIS v5.0.0 has no matching control. Accepted, see [control-tiers.md](../control-tiers.md).

**9. Prowler-only FAIL: 4.1 to 4.15 (CloudWatch metric filters and alarms), 15 failures.** Security Hub's CIS v5.0.0 standard contains **no controls for these**; Prowler implements them from the benchmark text. They fail because the trail does not send logs to CloudWatch Logs (decision e). **This corrects an earlier claim** in these docs that "CIS v5.0.0 has no CloudWatch metric-filter/alarm controls, so decision e causes no CIS failure": true for Security Hub's list, false for the benchmark as Prowler measures it. Why Security Hub's v5.0.0 omits them is not verified. The EventBridge alerts partly cover the intent (CloudTrail changes 4.5, KMS key changes 4.7, Config changes 4.9, and log-bucket policy changes for 4.8 only on that bucket), but they are not CloudWatch metric filters and would not satisfy the control text.

**10. Prowler-only PASS (5): 1.6 (root not used), 1.10, 1.12, 1.20 (IAM users managed centrally), 4.16 (Security Hub enabled).** Security Hub's CIS v5.0.0 has no separate control for these, or they are not measurable there. No action.

## What this comparison does not show

- Only `us-east-1` was scanned. CIS requirements that apply per region (flow logs, default security groups, Config) are evaluated for that region only.
- Prowler's PASS on a requirement with "no result" for the other tool is not extra assurance: it reflects what each tool can see, and the account is nearly empty.
- Scores are not comparable as percentages: the two tools count different things (Security Hub counts controls, Prowler counts resource-level rows), and each has requirements the other lacks. Compare control by control, as above.
