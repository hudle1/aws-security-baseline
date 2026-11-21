# Architecture decision records

Each decision that shaped this repo, in a short fixed format: context, options, decision, consequences, and who recommended and who decided. They were first recorded as questions in `design-decisions.md` and converted here on 2026-11-20 (Phase 7b). **Decided by** is always David; **Recommended by** says "Not recorded" where the history does not show a recommendation, rather than guessing.

[design-decisions.md](../design-decisions.md) holds David's own explanation of the decisions in his words.

| ADR | Question | Decision | Date | Status |
| --- | --- | --- | --- | --- |
| [001](001-config-delivers-to-shared-log-bucket.md) | Q-a | AWS Config delivers to the shared log-archive bucket | 2026-11-15 | Accepted |
| [002](002-separate-kms-keys-per-service.md) | Q-b | Separate KMS keys for CloudTrail and Config | 2026-11-15 | Accepted |
| [003](003-no-object-lock-in-v1.md) | Q-c | No S3 Object Lock on the log bucket in v1 | 2026-11-15 | Accepted |
| [004](004-cloudtrail-data-events-off.md) | Q-d | CloudTrail data events off; GuardDuty S3 Protection on | 2026-11-15 | Accepted |
| [005](005-cloudwatch-logs-and-cis-alarms-later.md) | Q-e | CloudTrail to CloudWatch Logs and CIS metric alarms: later (Tier 1) | 2026-11-15 | Accepted (premise corrected twice) |
| [006](006-detection-in-us-east-1-only.md) | Q-f | GuardDuty, Config and Security Hub in us-east-1 only | 2026-11-18 | Accepted |
| [007](007-no-forced-password-expiry.md) | Q-g | No forced password expiry (`max_password_age` unset) | 2026-11-16 | Accepted |
| [008](008-budget-keeps-credit-refund-filter.md) | Q-h | The imported budget keeps its "exclude credits and refunds" filter | 2026-11-16 | Accepted |
| [009](009-no-s3-access-logging-on-cloudtrail-bucket.md) | Q-i | No S3 server access logging on the CloudTrail bucket (CloudTrail.7): Tier 1 exception | 2026-11-18 | Accepted |
| [010](010-log-retention-365-and-30-days.md) | Q-j | Log retention: 365 days current, 30 days noncurrent versions | 2026-11-18 | Accepted |
| [011](011-account-wide-cloudtrail-log-decrypt.md) | Q-k | Who may decrypt CloudTrail logs: the account-wide AWS pattern | 2026-11-18 | Accepted |
| [012](012-real-time-alerts-in-v1.md) | Q-l | Real-time alerts on tampering and high-severity findings are in v1 | 2026-11-18 | Accepted (implemented and proven in Phase 5) |
| [013](013-config-continuous-recording.md) | Q-m | AWS Config records continuously | 2026-11-18 | Accepted |
| [014](014-config-uses-service-linked-role.md) | Q-n | Config uses the service-linked role | 2026-11-18 | Accepted |
| [015](015-guardduty-s3-protection-only.md) | Q-o | GuardDuty: S3 Protection only; every other paid plan explicitly disabled | 2026-11-18 | Accepted |
| [016](016-sns-topic-customer-managed-key.md) | Q-p | The alerts SNS topic is encrypted with a customer-managed key | 2026-11-18 | Accepted |
| [017](017-kms-tamper-rule-matches-any-key.md) | Q-q | The KMS tamper rule matches any key in the account | 2026-11-18 | Accepted |
| [018](018-free-quick-wins-and-test-finding.md) | Q-r | Fix four free failing controls; handle the test finding | 2026-11-20 | Accepted (implemented; see Consequences) |
| [019](019-accept-virtual-root-mfa-for-v1.md) | Q-s | IAM.6: accept virtual root MFA for v1; hardware key is a v1.1 item | 2026-11-20 | Accepted for v1 (revisit with the v1.1 hardware key) |
| [020](020-delete-default-vpcs.md) | Q-t | Delete the default VPC in every enabled region | 2026-11-20 | Accepted (deletion pending approval of the dry-run output) |
| [021](021-security-hub-fsbp-and-cis-in-scope.md) | - | Security Hub enables both FSBP and CIS AWS Foundations v5.0.0 | 2026-11-15 | Accepted |

## Adding a decision

Copy the structure of any ADR above, use the next number, and add a row here. Do not edit the decision of an accepted ADR: add a new ADR that supersedes it and change the old one's status to "Superseded by ADR-NNN". Dated corrections to facts (as in ADR-005) are fine.
