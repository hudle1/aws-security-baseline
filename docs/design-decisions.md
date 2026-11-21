# Design Decisions

**Written by David.**

These are my answers to seven interview-style questions about the choices in this project. I gave them in a chat on 2026-11-20; the words and the reasoning are mine. They were assembled with light edits only (formatting of commands and code terms). Each answer links to the decision records and evidence behind it. The full list of decisions, with options and consequences, is in [decisions/](decisions/README.md).

## 1. Two stacks: guardrails and baseline

**Question:** Why did you split the project into two Terraform stacks, `guardrails` and `baseline`, instead of one?

Guardrails (budget alarm, S3 Block Public Access, password policy) are free and should always be on, while the baseline (CloudTrail, GuardDuty, Security Hub, Config) costs money and gets torn down when I'm not demoing. I split them by lifecycle and cost so that tearing down to save money never weakens the account's protections. With one stack, a single destroy would also delete the budget alarm, turn off S3 Block Public Access, remove the password policy, and even delete my original budget, since it's imported into Terraform. The split limits the blast radius of Terraform operations, but it isn't a security boundary, because both stacks share the same account and credentials.

*Related: [ADR-018](decisions/018-free-quick-wins-and-test-finding.md) (guardrails quick wins), [ADR-008](decisions/008-budget-keeps-credit-refund-filter.md) (the imported budget), [teardown.md](operations/teardown.md)*

## 2. One shared log bucket, separate KMS keys

**Question:** The CloudTrail and Config logs go into one shared bucket, but each service has its own KMS key. Why share the bucket but separate the keys?

I share one bucket because it acts like a single hardened log archive: one place to secure, one set of protections (versioning, Block Public Access, TLS-only, encryption), and one teardown. Each service can only write to its own folder, locked to my account with source conditions, which mirrors how a real log-archive account works. I separated the keys because it costs only about a dollar a month more and is the more secure option: if one key policy is ever wrong, it doesn't expose the other service's logs, and each policy is simpler to read and review. In short, I consolidate where it reduces what I have to harden, and separate where it limits blast radius.

*Related: [ADR-001](decisions/001-config-delivers-to-shared-log-bucket.md), [ADR-002](decisions/002-separate-kms-keys-per-service.md)*

## 3. No Object Lock in v1, and what production would do

**Question:** The log bucket has versioning and CloudTrail log file validation, but no S3 Object Lock, and a `terraform destroy` even erases the logs. Why did you accept that, and what would you do differently in production?

I chose not to use S3 Object Lock in v1 because in a single sandbox account the real threat is a compromised admin, and governance mode doesn't stop an admin, while compliance mode would make the logs undeletable until retention expires and break my one-command teardown. So v1 focuses on detection instead of prevention: versioning keeps prior copies, CloudTrail log file validation proves which logs existed and whether they changed (888 of 888 files validated, though only when someone runs it), and real-time alerts fire on changes to the bucket policy or versioning, which I proved live. The `force_destroy` setting that lets `terraform destroy` erase the logs is a deliberate sandbox-only trade-off. In production I'd send logs to a separate log-archive account through an organization trail, enable compliance-mode Object Lock with a defined retention period, remove `force_destroy`, and use SCPs to deny deleting logs or stopping the trail, so even an admin in the workload account couldn't erase the evidence.

*Related: [ADR-003](decisions/003-no-object-lock-in-v1.md), [ADR-012](decisions/012-real-time-alerts-in-v1.md), [validate-logs evidence](evidence/validate-logs-output.txt)*

## 4. Detection in us-east-1 only

**Question:** CloudTrail is multi-region, but GuardDuty, Config, Security Hub and the alerts run in us-east-1 only. What attack does that leave open, and how did you compensate?

Running detection only in us-east-1 leaves an attacker with stolen credentials free to use a region nobody watches, for example launching crypto-mining instances in eu-west-1. That's a common real-world pattern, and in my setup it wouldn't raise a GuardDuty finding or a real-time alert. I compensated in two ways. First, CloudTrail is multi-region, so the activity is still recorded as evidence in every region. Second, my budget alarm tracks gross spend, with credits and refunds excluded, so a cost spike from mining in any region would trigger an alert, within hours to a day rather than minutes. I also deleted the default VPC in all 17 regions, which removes ready-made networking an attacker could use, although they could still create their own, and that would also be logged. The first v1.1 item is GuardDuty in every enabled region with findings forwarded to my us-east-1 alerts, and in production I'd use an SCP that denies unused regions entirely, which prevents the attack instead of just detecting it.

*Related: [ADR-006](decisions/006-detection-in-us-east-1-only.md), [ADR-020](decisions/020-delete-default-vpcs.md), [default-VPC evidence](evidence/default-vpc-deletion.md)*

## 5. Alert rules versus GuardDuty

**Question:** You tested the CloudTrail `StopLogging` alert live, and GuardDuty also reacted to the same action. What did comparing the two teach you about relying on each?

The EventBridge rule matches the exact StopLogging API call, so it's deterministic and fast: the alert email arrived within the same minute. GuardDuty reacted too, but about 22 minutes later, and it rated the finding Low (severity 2), which as far as I know is how GuardDuty classifies that finding type by design rather than a judgment about my specific call. Since my GuardDuty alert rule only forwards severity 7 and above, that finding would never have emailed me. The lesson is defense in depth: I use exact-match rules for known critical tampering actions, where I want a guaranteed, immediate alert, and GuardDuty for behavior I can't predict in advance. I also learned that a severity threshold is a trade-off: it cuts noise but can hide low-severity events that matter in context, which is exactly why I built specific tampering rules instead of relying only on GuardDuty's high-severity findings.

*Related: [ADR-012](decisions/012-real-time-alerts-in-v1.md), [alerts.md](components/alerts.md), [GuardDuty finding evidence](evidence/guardduty-cloudtrail-logging-disabled.md)*

## 6. Accepted failures versus fixed ones

**Question:** Your scorecard still has failing controls (for example IAM.6, CloudTrail.7, S3.22 and S3.23). Why accept those instead of fixing them, and how did you decide which failures to fix?

I treated the score as a tool, not the goal. Every failing control got the same question: what's the real risk, what does fixing it cost, and is there a compensating control? Anything free and high-value I fixed right away. That's why I added EBS default encryption, the security contact, the support role and the SSM sharing block (four failures turned into passes), and deleted the default VPC in all 17 regions. The ones I accepted each have a documented tier, reason, compensating control and target date. IAM.6 is hardware MFA for root: root already has virtual MFA, no access keys, and is never used day to day, so a FIDO key is a v1.1 item. CloudTrail.7 is access logging on the log bucket: it would add a second bucket to harden, and against a compromised admin it adds little, since log file validation already detects tampering. S3.22 and S3.23 are object-level logging, which I turned off for cost and noise, with GuardDuty S3 Protection analyzing that activity for anomalies instead. In production, with real data and more users, I'd revisit each of these, but an auditor cares more that every gap is known, justified and time-bound than about a perfect score.

*Related: [control-tiers.md](control-tiers.md), [ADR-009](decisions/009-no-s3-access-logging-on-cloudtrail-bucket.md), [ADR-004](decisions/004-cloudtrail-data-events-off.md), [ADR-019](decisions/019-accept-virtual-root-mfa-for-v1.md), [ADR-020](decisions/020-delete-default-vpcs.md)*

## 7. Building with AI: what the guardrails are for

**Question:** You built this with Claude Code, and the README says you set guardrails on it. Looking back, which guardrail mattered most, and what is one thing you would not let the AI do on its own?

The guardrail that mattered most was that Claude Code couldn't change its own permissions. I denied it edit access to its settings file, and later closed a gap where it could have edited the file through shell commands, so every rule loosening had to come from me. On top of that, anything that changed AWS or GitHub needed my approval: `terraform apply` and `destroy`, `git push` and GitHub API writes. Branch protection backed that up: when one of its commits landed on main by mistake, GitHub rejected the push, and it recovered by moving the commit to a branch. The one thing I wouldn't let the AI do on its own is approve changes to production, meaning applying infrastructure or merging to main. It was careful (it even refused to treat a verification checklist as approval to apply), but it also overclaimed several times, writing that things were proven when they weren't. Independent checks caught those: a second reviewer, live tests, and Prowler as a second scanner. So my rule is that the AI builds and explains, while a human approves, and anything it claims gets verified against evidence.

*Related: [README section 11](../README.md#11-how-i-built-this-with-ai), [CLAUDE.md](../CLAUDE.md)*

---

## Evidence notes (added by Claude; not part of David's answers)

Checked against the repo and the live account on 2026-11-20, so the answers above can be quoted safely.

- **Two stacks (1):** matches `make.ps1`, where `destroy` removes the baseline only and `destroy-all` (which asks you to type `destroy-all`) also removes the guardrails and the imported budget.
- **Alerts on the bucket (3):** the `logbucket-tamper` alert was proven live for bucket policy changes (real `PutBucketPolicy` calls). The same rule also lists `PutBucketVersioning`, but that call was never triggered in a test, so for versioning the rule is deployed and enabled, not live-proven.
- **Budget alarm timing (4):** "within hours to a day" is a reasonable expectation from how AWS cost data arrives; the alarm has not been triggered, so the latency is not measured. The default VPCs were deleted in all 17 regions and none remain (evidence file linked above).
- **GuardDuty severity (5):** one finding was observed, severity 2.0 (Low), about 22 minutes after the call. That GuardDuty always rates this finding type Low is not verified, so the hedge in the answer ("as far as I know") should stay.
- **Accepted failures (6):** the four quick-win controls (EC2.7, Account.1, IAM.18, SSM.7) were re-checked in Security Hub and show PASSED. "Root is never used day to day": Prowler's check (CIS 1.6) confirms no root use in the last day only; CloudTrail records every root sign-in. `CloudTrail.7` is CIS v5.0.0 3.4 only, severity LOW (verified live), and Prowler also fails it.
- **AI guardrails (7):** the 2026-11-18 sequence is confirmed in git: the commit (`369d169`) was made on local `main` at 00:39:25 MT, about 15 seconds after PR #4 merged, then moved to branch `docs/phase5-done-criteria`, which became PR #5 (merged 07:41:57 UTC), with no force push. The push rejection by branch protection leaves no trace in git history, so that detail is David's account. The settings-file deny rules were not inspected by Claude (a read of that file was denied during this session, consistent with the rule).
