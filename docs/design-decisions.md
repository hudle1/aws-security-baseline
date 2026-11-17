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
