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

**Q-f. Detection regions (OPEN, decide in Phase 5).**
CloudTrail is multi-region, but GuardDuty, Config and Security Hub are regional and v1 deploys them in us-east-1 only. An attacker acting in another enabled region is logged but not detected (threat model #10).
Options: (1) GuardDuty in all 17 enabled regions (near-$0 when idle, more resources/teardown); (2) us-east-1 only, documented residual risk; (3) opt out of unused opt-in regions (the 17 default regions can't be disabled without Organizations SCPs).
Choice: _pending_.

**Scope change: CIS in scope.**
Security Hub enables both AWS FSBP and the CIS AWS Foundations Benchmark. Latest supported version confirmed as **v5.0.0** via `aws securityhub describe-standards` (2026-11-15); which controls v5.0.0 contains is checked in Phase 5. Default standards stay off. Prowler gives an independent CIS report in Phase 7.

### Phase 4 design choices (2026-11-18)

**Q-i. Should the CloudTrail bucket have S3 server access logging (CloudTrail.7)?**
Finding: CloudTrail.7 maps to CIS v1.2, v1.4 and v3.0 only. It is not in CIS v5.0.0 or FSBP (checked against the AWS Security Hub control docs, 2026-11-18), so neither enabled standard checks for it.
Options: (1) Tier 1 exception, no second bucket; (2) in scope: a second hardened access-log bucket plus logging on the log bucket.
Choice: **1, Tier 1 exception.**
Reasoning: a second bucket would itself need BPA, versioning and a policy, and Checkov would then flag that bucket for having no logging, which is a loop. Recorded in `control-tiers.md`; `CKV_AWS_18` is skipped in code with this reason.
Related finding: CloudTrail.5 (CloudWatch Logs) is CIS v5.0.0 3.4, so decision e makes it fail by design. It was already listed in `control-tiers.md` and is now marked as confirmed.

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
