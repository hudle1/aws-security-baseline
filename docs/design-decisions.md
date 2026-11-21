# Design Decisions

(Written by David.)

## Questions for David

(Claude adds design-choice questions and David's chosen answers here.)

### Phase 2 design choices (decided 2026-11-15)

**Q-a. Where does AWS Config deliver snapshots?**
Options: (1) share the CloudTrail log bucket with a separate prefix; (2) its own bucket.
Choice: **1, shared log-archive bucket.**
David's reasoning: one hardened log-archive bucket, with each service limited to its own prefix using `aws:SourceAccount` / `aws:SourceArn` conditions. Mirrors a real log-archive account and keeps teardown simple.

**Q-b. One KMS key or separate keys?**
Options: (1) one customer-managed key for CloudTrail + Config (~$1/mo); (2) separate keys (~$2/mo).
Choice: **2, separate keys.**
David's reasoning: about $1/month more, but a smaller blast radius if one key policy is wrong, and each policy is simpler to read.
Implementation note: both services write to the shared bucket; CloudTrail encrypts with the CloudTrail key (set on the trail), Config with the Config key (`s3_kms_key_arn` on the delivery channel). The bucket's default encryption key only applies to writers that don't specify one.

**Q-c. S3 Object Lock on the log bucket?**
Options: compliance mode; governance mode; none for v1.
Choice: **none for v1.**
David's reasoning: a compromised admin can bypass governance mode, and compliance mode breaks one-command teardown. v1 detects tampering with CloudTrail log file validation + bucket versioning. Prevention (compliance-mode Object Lock in a separate log-archive account) goes on the roadmap.

**Q-d. CloudTrail data events (S3/Lambda)?**
Options: on; off.
Choice: **off.**
David's reasoning: management events cover the attacks in the threat model. GuardDuty S3 Protection must be enabled in Phase 5 so S3 detection doesn't depend on trail data events.

**Q-e. CloudTrail to CloudWatch Logs + CIS metric alarms?**
Options: v1; Tier 1 later.
Choice: **Tier 1 later.**
David's reasoning: with the CIS standard enabled, the CIS alarm controls may fail. Each is listed in `control-tiers.md` as Tier 1 with the reason (cost, and GuardDuty already alerts on root credential use and CloudTrail being stopped). Phase 5: check whether the current Security Hub CIS version still includes those controls.
**Phase 5 answer (verified 2026-11-19):** CIS v5.0.0 has 40 controls in Security Hub and **none are CloudWatch metric-filter or alarm controls**, so decision e causes no CIS failure. The Phase 2 premise ("CIS alarm controls may fail") applied to older CIS versions.

**Q-f. Detection regions (OPEN, decide in Phase 5).**
CloudTrail is multi-region, but GuardDuty, Config and Security Hub are regional and v1 deploys them in us-east-1 only. An attacker acting in another enabled region is logged but not detected (threat model #10).
Options: (1) GuardDuty in all 17 enabled regions (near-$0 when idle, more resources/teardown); (2) us-east-1 only, documented residual risk; (3) opt out of unused opt-in regions (the 17 default regions can't be disabled without Organizations SCPs).
Choice: **2, us-east-1 only for v1. Decided by David 2026-11-18.**
Compensating controls: multi-region CloudTrail (evidence in every region) and the gross-spend budget alarm (catches cost spikes such as crypto-mining in any region).
Roadmap: first v1.1 item is "GuardDuty in all enabled regions with cross-region alert forwarding to us-east-1". Production / Tier 2 fix: an SCP denying unused regions. Threat model #10 residual risk updated to match.

**Scope change: CIS in scope.**
Security Hub enables both AWS FSBP and the CIS AWS Foundations Benchmark. Latest supported version confirmed as **v5.0.0** via `aws securityhub describe-standards` (2026-11-15); which controls v5.0.0 contains is checked in Phase 5. Default standards stay off. Prowler gives an independent CIS report in Phase 7.

### Phase 4 design choices (2026-11-18)

**Q-i. Should the CloudTrail bucket have S3 server access logging (CloudTrail.7)?**
Finding (**corrected 2026-11-19**): an earlier version of this note said CloudTrail.7 was in neither enabled standard. That was wrong. With CIS v5.0.0 enabled, Security Hub reports `CloudTrail.7` as a CIS v5.0.0 control (3.4, "S3 access logging on the CloudTrail bucket") and it **fails**. The Tier 1 exception below still stands; only the premise changed.
Options: (1) Tier 1 exception, no second bucket; (2) in scope: a second hardened access-log bucket plus logging on the log bucket.
Choice: **1, Tier 1 exception.**
Reasoning: a second bucket would itself need BPA, versioning and a policy, and Checkov would then flag that bucket for having no logging, which is a loop. Recorded in `control-tiers.md`; `CKV_AWS_18` is skipped in code with this reason.
Related finding (**corrected 2026-11-19**): CloudTrail.5 (CloudWatch Logs) is an FSBP control only, not CIS v5.0.0 3.4 as this note said. It still fails by design because of decision e.

**Q-j. Log retention.**
Options: 90 days (cheaper, shorter evidence window); 365 days (covers a typical SOC 2 audit window and slow investigations).
Choice: **365 days for current objects, 30 days for noncurrent versions** (variables `log_retention_days`, `noncurrent_retention_days`; the first has a 90-day minimum). **Confirmed by David 2026-11-18.**
David's reasoning: covers a typical audit window and slow investigations, for pennies. Digest files expire on the same schedule, so `validate-logs` only works inside that window.

**Q-k. Who may decrypt CloudTrail logs?**
Options: (1) AWS's documented pattern: any principal in this account, limited to CloudTrail-encrypted data by encryption context; (2) a named log-reader role only.
Choice: **1, AWS's documented account-wide pattern. Confirmed by David 2026-11-18.**
David's reasoning: S3 read access is still required as a second lock, because reading a log needs both S3 permissions and `kms:Decrypt`. Trade-off: the key statement grants decrypt without needing an IAM allow. Production improvement: a named log-reader role (threat model #3).

### Scope change: real-time alerts move into v1 (2026-11-18)

**Q-l. Should real-time alerts on tampering and high-severity findings be in v1?**
Options: (1) Tier 1, later (as recorded in the Phase 2 threat model); (2) v1, built in Phase 5.
Choice: **2, v1, built in Phase 5.**
David's reasoning: it closes the "no real-time alert" gaps for log tampering and key deletion at about $0 cost.
Scope (recorded in `CLAUDE.md`, nothing built yet):
- One SNS topic with an email subscription (alert email from `baseline.tfvars`; David confirms the subscription).
- EventBridge rules for: CloudTrail `StopLogging` / `DeleteTrail` / `UpdateTrail`; KMS `ScheduleKeyDeletion` / `DisableKey` / `PutKeyPolicy` on our keys; S3 `PutBucketPolicy` / `DeleteBucketPolicy` / `PutBucketVersioning` on the log bucket; Config `StopConfigurationRecorder` / `DeleteDeliveryChannel`; GuardDuty findings with severity >= 7; new active IAM Access Analyzer findings.
Limits (to state in the Phase 5 component doc and README):
- us-east-1 only: EventBridge rules work only in the region where they are created.
- The API-call rules depend on the trail running: EventBridge receives CloudTrail-sourced events only while a trail with logging is on ([AWS docs](https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-service-event-cloudtrail.html)). That `StopLogging` itself is still delivered is David's understanding; verify by testing in Phase 5.
- Detect-only: a compromised admin can delete the rules or the topic. Prevention still needs SCPs (Tier 2).
Cost note: "about $0" holds for EventBridge and SNS email at this volume. If the SNS topic needs a customer-managed KMS key, that adds about $1/month (open item for Phase 5).
Effect on other docs: `control-tiers.md` alert rows now say "Phase 5, v1". Threat model rows #1, #4, #7, #8, #9 and #21 still say "Tier 1: EventBridge rule" in their residual-risk column. **David decided (2026-11-18): update them when Phase 5 ships, not now.** This is in the Phase 5 definition of done in `CLAUDE.md`.
SNS topic encryption: decided in Phase 5. David's current leaning is a customer-managed key (most secure, about $1/month) if EventBridge cannot publish to a topic encrypted with the AWS-managed `aws/sns` key (to verify first).
The Phase 4 stack stays deployed through Phase 5 (it is the base Phase 5 builds on). Teardown happens in Phase 7.

### Phase 5 design choices (2026-11-18)

**Q-m. Config recording frequency.**
Options: (1) continuous ($0.003 per configuration item, billed only when a resource changes); (2) daily ($0.012 per item, one item per resource per day).
Choice: **1, continuous.** Decided by David 2026-11-18. This replaces "daily" in the `CLAUDE.md` v1 scope, `architecture.md`, `control-tiers.md` and `compliance-mapping.md`.
David's reasoning: continuous bills only on change, so in a low-change sandbox it is likely cheaper than daily, and it records a change within minutes instead of up to 24 hours (supports threat model #7).

**Q-n. Config IAM role.**
Options: (1) AWS service-linked role `AWSServiceRoleForConfig`; (2) custom role.
Choice: **1, service-linked role.** Nothing for us to over-broaden. Implementation notes: Terraform creates the role explicitly (`aws_iam_service_linked_role`) because a fresh account does not have it until Config is first enabled. The role has **no KMS permissions**, so with an SLR Config delivers to S3 as the `config.amazonaws.com` service principal; the Config key policy therefore grants that principal (with `aws:SourceAccount` and `aws:SourceArn`), not the role (see troubleshooting #10).

**Q-o. GuardDuty protection plans.**
Options: (1) S3 Protection only, every other paid plan explicitly `DISABLED`; (2) add Lambda; (3) everything on.
Choice: **1.** `guardduty-triage` (P2, the next sprint project) will deploy a Lambda: **enable Lambda Protection when P2's Lambda is deployed.**

**Q-p. SNS topic encryption.**
Finding (verified 2026-11-18 against the AWS Knowledge Center article "SNS not getting EventBridge notification" and the SNS key-management docs): EventBridge cannot publish to a topic encrypted with the AWS-managed `aws/sns` key, because that key's policy cannot be edited to grant EventBridge access. The key policy for a customer-managed key also must not use `aws:SourceAccount` / `aws:SourceArn` conditions for EventBridge delivery.
Options: (1) customer-managed key (about $1/month); (2) `aws/sns` (does not work); (3) unencrypted with a justified skip.
Choice: **1, customer-managed key.** Scoping to our rules is done in the topic policy (`aws:SourceArn` = our rule ARNs) instead.

**Q-q. How the KMS tamper rule matches keys.**
Options: (1) our three keys by ID and ARN; (2) any KMS key in the account; (3) key ID only.
Choice: **2, any KMS key in the account.** Never stale, and a new key is covered automatically. Trade-off: also alerts on harmless key work in the sandbox.

**Q-r. What to do with the free failing controls and the test finding (decided 2026-11-20).**
- **Quick wins:** fix `EC2.7` (EBS default encryption), `Account.1` (security contact), `IAM.18` (support role) and `SSM.7` (block public SSM document sharing) in the guardrails stack, as a small follow-up PR after Phase 5 merges. Account contact details live in `guardrails.tfvars` (gitignored), placeholders in the example file.
- **Test finding:** the real GuardDuty `Stealth:IAMUser/CloudTrailLoggingDisabled` finding from the StopLogging test stays unarchived until the Phase 7 screenshots, then is archived.
- **`docs/operations/deploy.md`:** written in Phase 7.

### Open question (added 2026-11-20, Phase 7a)

**Q-s. Fix IAM.6 (hardware MFA on the root user) or keep it as an accepted risk?**
Facts (checked live): root MFA is on, it is a virtual authenticator-app device, there are no root access keys, and Security Hub rates IAM.6 CRITICAL. The Prowler CIS run (docs/compliance/) reports the same control.
Options: (1) **keep the accepted risk** (Tier 1, current): costs nothing; compensating controls are root MFA, no root keys, SSO for daily work and CloudTrail; the scorecard keeps one CRITICAL failure that the README must explain. (2) **register a FIDO2 hardware security key as root MFA** (one-time cost for the key, roughly $25 to $55; buying two and storing one separately is the usual advice): IAM.6 should then pass; the cost is the key, the effort, and a recovery plan if it is lost. Whether Security Hub also requires the virtual device to be removed is unverified. (3) **add a root `ConsoleLogin` alert** (EventBridge rule, v1.1) as an extra compensating control with either option: free, and detects root use in about a minute like the other alert rules.
Choice: **pending David.**

### Phase 3 design choices (2026-11-16)

**Q-g. Should the IAM password policy force password expiry (`max_password_age`)?**
Options: (1) set 90 days or less (satisfies Checkov `CKV_AWS_9`); (2) leave unset (never expires).
Choice: **2, unset.**
David's reasoning (from the code comment): NIST SP 800-63B advises against forced periodic rotation because it pushes users toward weak, predictable passwords; CIS v5.0.0 doesn't require it; Security Hub IAM.7 passes without it. `CKV_AWS_9` is skipped in `main.tf` with this justification.

**Q-h. Should the imported budget keep its "exclude credits and refunds" filter?**
The live budget `monthly-10-usd` excludes `Credit` and `Refund` records, so it measures gross usage. The Terraform draft had no matching `filter_expression`, so the first plan removed it.
Options: (1) add the matching `filter_expression` so the import changes only the notifications (alerts track gross spend); (2) accept net-of-credits (simpler code; alerts fire later than real usage when credits exist).
Choice: **1, keep the filter.**
David's reasoning: gross spend, so credits can't mask a compromise-driven cost spike.
Implementation notes: the provider requires `metrics` whenever `filter_expression` is set, so `metrics = ["UnblendedCost"]` (the live value) is also in code. `billing_view_arn` is set to the account's `primary` billing view (built from `var.account_id`) so the import doesn't change it. AWS's API reference doesn't say what omitting it does, so matching it is the safe choice, and it also keeps `plan` clean after apply.
