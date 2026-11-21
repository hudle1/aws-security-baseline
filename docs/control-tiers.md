# Control Tiers

How I'd sequence these controls in a real company. **v1 of this repo demonstrates all Tier 0 controls plus selected Tier 1 controls** (Security Hub, AWS Config, real-time email alerts), because a portfolio needs to show the posture scorecard.

- **Tier 0: day 1.** Free or near-free, prevents or detects the most common breaches.
- **Tier 1: 30–90 days.** Real value, but adds cost that grows with resources, or needs someone to act on its output.
- **Tier 2: org maturity.** Needs multiple accounts, a team, or budget.

## Tier 0: day 1 (all in v1)

| Control | Stack | Reasoning (David) |
| --- | --- | --- |
| SSO with MFA, no access keys, root MFA | Outside Terraform (verified in pre-flight) | Identity is the perimeter; most breaches start with credentials |
| CloudTrail (multi-region, KMS, log validation) | baseline | Without logs nothing else can be investigated |
| GuardDuty + S3 Protection | baseline | Cheap managed threat detection, no tuning needed |
| Account-level S3 Block Public Access | guardrails | Free; stops the most common cloud data leak |
| Budget alarm (actual + forecast) | guardrails | Cost spikes are often the first sign of stolen credentials |
| IAM password policy | guardrails | Free and CIS-required. With SSO there are no IAM console users today, so it's defense in depth for any IAM user created later (e.g. break-glass) |
| IAM Access Analyzer (external access) | guardrails | Free, persistent, a CIS control; flags any resource shared outside the account |
| Minimal IR runbook: compromised credentials | `docs/runbook-compromised-credentials.md` (Phase 7) | Costs only time; detection without a response plan is just noise |

## Tier 1: 30–90 days

| Control | In v1? | Reasoning (David) |
| --- | --- | --- |
| Security Hub (FSBP + CIS) | **Yes** | Cost grows with resources and findings need someone to triage; deployed in v1 to show the scorecard |
| AWS Config (limited types, continuous) | **Yes** | Same as Security Hub, which depends on it |
| CloudTrail → CloudWatch Logs + CIS metric alarms | No | Cost; GuardDuty already alerts on root credential use and CloudTrail being stopped (decision e) |
| EventBridge + SNS email alerts: CloudTrail stop/delete/update, KMS key deletion/disable/policy, log bucket policy/versioning, Config recorder stop, GuardDuty severity >= 7, new Access Analyzer findings | **Phase 5, v1** (decision Q-l) | Closes the "no real-time alert" gaps (threat model #1, #4, #7, #8, #9, #21) at about $0. Limits: us-east-1 only; API-call rules depend on the trail running; detect-only |
| Remote Terraform state (S3, versioned, locking) | No | Threat model #13; not needed for one person on one laptop |
| GuardDuty in all enabled regions, with cross-region alert forwarding to us-east-1 | **No: first v1.1 item** (decision Q-f) | Threat model #10. v1 is us-east-1 only; compensated by the multi-region trail and the gross-spend budget alarm |
| Distinct email subject per alert rule | No: v1.1 item | Every alert currently has the same subject, so Gmail groups them into one conversation and a new alert can hide in an old thread (troubleshooting #19). An EventBridge input transformer changes the message body only; it cannot set the SNS subject. Options: (1) a small Lambda formatter (EventBridge to Lambda to `sns:Publish` with a per-rule `Subject`): reliable, but adds code, a role and a log group to maintain; (2) one topic and subscription per rule: more resources, and it is **unverified** whether it changes the subject (it changes the topic name, not the subject, so grouping may remain); (3) a different channel such as Slack through AWS Chatbot, where each message is separate. Option 1 is the likely choice |

## Tier 2: organizational maturity (out of scope)

| Control | Reasoning |
| --- | --- |
| AWS Organizations + SCPs (deny StopLogging, **deny unused regions** (production fix for threat model #10), protect security services) | The only fix for "a compromised admin can disable everything" |
| Log-archive account with compliance-mode Object Lock | Prevention for log tampering (decision c roadmap) |
| Delegated security account (GuardDuty / Security Hub admin) | Separates detection from the workload it watches |
| SIEM (Security Lake / OpenSearch / Splunk) | Needs data volume and analysts to justify |
| IR testing (tabletops, game days) | Needs a team and runbooks first |

## Controls that fail by design (live results, Phase 5)

Measured on 2026-11-19, a few minutes after both standards became `READY` (`securityhub get-findings`, status FAILED). Counts will move as Config rules finish evaluating; re-check in Phase 7.

| Result | Count |
| --- | --- |
| Passed | 112 |
| Failed | 31 |
| Warning: cannot be evaluated (`CONFIG_RECORDER_MISSING_REQUIRED_RESOURCE_TYPES`) | 267 |

**The 267 unevaluated controls are the real cost of recording only 7 Config resource types** ([components/config.md](components/config.md)). They are *not measured*, which is different from passed. Recording every type would evaluate them at a cost that grows with the resources in the account. Accepted for v1 (Tier 1); a decision to revisit if the scorecard is shown to others as a score.

**Corrections to earlier drafts (verified live 2026-11-19):**
- **Q-e answered:** CIS v5.0.0 has **40 controls in Security Hub and none are CloudWatch metric-filter or alarm controls**. Decision e (no CloudWatch Logs) therefore causes **no CIS failure**; the old "CloudWatch.1 to 14" row is removed. (`CloudTrail.5`, CloudWatch Logs on the trail, is an FSBP control only.)
- **`CloudTrail.7` is in CIS v5.0.0** (control 3.4, "S3 access logging on the CloudTrail bucket") and **fails**. An earlier Phase 4 draft said it was in neither standard; that was wrong. The Tier 1 exception still stands, for the reason given (it needs a second hardened bucket).
- `Config.1` is CIS 3.3 and FSBP; it fails because of limited types.

Dates are provisional (set 2026-11-15) and use the 90-day maximum from the risk-acceptance template.

### Failed controls that are in CIS v5.0.0

| Security Hub control | What it requires | Why it fails | Tier | Compensating control | Target |
| --- | --- | --- | --- | --- | --- |
| Config.1 (CIS 3.3, also FSBP) | Config enabled, recording all resources, with the service-linked role | Only 7 resource types are recorded (cost) | 1 | Config records the security-relevant types; multi-region CloudTrail logs every API call | 2027-02-13 |
| CloudTrail.7 (CIS 3.4) | S3 access logging on the CloudTrail bucket | Needs a second hardened access-log bucket (Phase 4 decision Q-i; Checkov `CKV_AWS_18` skipped) | 1 | Bucket-level actions are CloudTrail management events; object integrity via log file validation | 2027-02-13 |
| S3.22, S3.23 | Object-level write / read logging for S3 | Decision d: CloudTrail data events off | 1 | GuardDuty S3 Protection is on (anomaly-based, needs a baseline) | 2027-02-13 |
| IAM.6 (also FSBP) | Hardware MFA for the root user | Root uses a virtual/passkey MFA (verify which) | 1 | Root has MFA and no access keys; GuardDuty alerts on root credential use | 2027-02-13 |
| IAM.18 | A support role exists (`AWSSupportAccess`) | Not created | 0 candidate | None needed (no users to delegate support to) | follow-up PR (guardrails), decided 2026-11-20 |
| Account.1 (also FSBP) | Security contact information set on the account | Not set | 0 candidate | None | follow-up PR (guardrails), decided 2026-11-20 |
| EC2.7 (also FSBP) | EBS default encryption enabled | Not enabled; no EBS volumes exist | 0 candidate | No EC2 or EBS in the sandbox | follow-up PR (guardrails), decided 2026-11-20 |

**Quick wins (decided 2026-11-20, built in the guardrails quick-wins PR, [component doc](components/account-quick-wins.md); not yet applied):** `EC2.7`, `Account.1`, `IAM.18` and FSBP `SSM.7` (CRITICAL, "block public sharing of SSM documents") are free account settings. They go in the **guardrails** stack as a small follow-up PR after Phase 5 merges, and would turn 4 failures into passes. The `Account.1` contact details go in `guardrails.tfvars` (gitignored) with placeholders in the example file.

### Failed controls that are FSBP only

| Security Hub control(s) | Why it fails | Tier | Compensating control | Target |
| --- | --- | --- | --- | --- |
| GuardDuty.5, .7, .8, .9, .11, .12, .13 | The matching GuardDuty plans (EKS audit/runtime, EC2/ECS runtime, EBS malware, RDS login) are `DISABLED` by decision Q-o: no such workloads, billed per use | 1 | Foundational detection and S3 Protection stay on | 2027-02-13 |
| GuardDuty.6 | Lambda Protection `DISABLED` | 1 | **Enable it when P2's Lambda (`guardduty-triage`) is deployed**; expected to pass then | with P2 |
| Inspector.1, .2, .3, .4 | Amazon Inspector not enabled (EC2, ECR, Lambda code and standard scanning). No such workloads; per-resource cost | 1 | None needed until workloads exist | 2027-02-13 |
| Macie.1 | Macie not enabled; no S3 data to classify; cost | 1 | Log bucket holds logs only | 2027-02-13 |
| EC2.10, .55, .56, .57, .58, .60 | VPC interface endpoints for EC2, ECR, SSM etc. in the default VPC. Interface endpoints cost money per hour; nothing runs in the VPC | 1 | No workloads in default VPCs | 2027-02-13 |
| CloudTrail.5 | Decision e: no CloudWatch Logs integration on the trail | 1 | Logs in S3 and `lookup-events`; EventBridge alerts cover trail tampering | 2027-02-13 |
| S3.9 | Server access logging on S3 buckets (same reason as CloudTrail.7) | 1 | As CloudTrail.7 | 2027-02-13 |
| SSM.6 | SSM Automation CloudWatch logging; no Automation in use | 1 | None needed | 2027-02-13 |
| SSM.7 | SSM document public sharing block not set (see quick wins above) | 0 candidate | No SSM documents exist | follow-up PR (guardrails), decided 2026-11-20 |

Not in the failed list but previously predicted: `EC2.2` / `EC2.6` (default security group, VPC flow logs) and `IAM.28` were not among the 31 failures at this check; whether they are unevaluated (`WARNING`) or passed is **not yet verified**: check in Phase 7.
