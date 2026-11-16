# Control Tiers

How I'd sequence these controls in a real company. **v1 of this repo demonstrates all Tier 0 controls plus selected Tier 1 controls** (Security Hub, AWS Config), because a portfolio needs to show the posture scorecard.

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
| AWS Config (limited types, daily) | **Yes** | Same as Security Hub, which depends on it |
| CloudTrail → CloudWatch Logs + CIS metric alarms | No | Cost; GuardDuty already alerts on root credential use and CloudTrail being stopped (decision e) |
| EventBridge alerts on KMS, bucket policy, GuardDuty changes | No | Closes "no real-time alert" gaps (threat model #4, #7, #8) |
| Remote Terraform state (S3, versioned, locking) | No | Threat model #13; not needed for one person on one laptop |
| GuardDuty in all enabled regions | Pending Q-f | Threat model #10; decided in Phase 5 |

## Tier 2: organizational maturity (out of scope)

| Control | Reasoning |
| --- | --- |
| AWS Organizations + SCPs (deny StopLogging, region deny, protect security services) | The only fix for "a compromised admin can disable everything" |
| Log-archive account with compliance-mode Object Lock | Prevention for log tampering (decision c roadmap) |
| Delegated security account (GuardDuty / Security Hub admin) | Separates detection from the workload it watches |
| SIEM (Security Lake / OpenSearch / Splunk) | Needs data volume and analysts to justify |
| IR testing (tabletops, game days) | Needs a team and runbooks first |

## CIS controls expected to fail by design

Target: CIS AWS Foundations Benchmark **v5.0.0** (latest Security Hub supports, confirmed 2026-11-15). Security Hub control IDs are listed; whether each is part of v5.0.0 is to **verify in Phase 5** against the enabled standard.

| Security Hub control | CIS requirement | Why it fails in v1 | Tier |
| --- | --- | --- | --- |
| CloudWatch.1–14 (verify they exist in the current CIS version) | Metric filters + alarms for root use, IAM/CloudTrail/KMS/S3 policy changes, etc. | Decision e: CloudWatch Logs integration deferred | 1 |
| CloudTrail.5 | Trail integrated with CloudWatch Logs | Decision e | 1 |
| S3.22 / S3.23 (verify) | Object-level logging for S3 write / read events | Decision d: data events off; GuardDuty S3 Protection covers detection | 1 |
| Config.1 / CIS "Config in all regions" (verify) | Config recording all resources in all regions | Limited resource types, us-east-1 only (cost) | 1 |
| IAM.28 / Access Analyzer "all regions" (verify) | Access Analyzer in every region | us-east-1 only unless Q-f changes it | 1 |
| CloudTrail.7 (verify) | Server access logging on the CloudTrail bucket | Needs a second bucket; candidate to add in Phase 4 | 1 |
| EC2.2 / EC2.6 (verify) | Default security group restricts all traffic; VPC flow logs | Default VPCs exist in the sandbox; decide in Phase 5 (restrict default SGs vs accept) | 1 |
| IAM.6 (verify) | Hardware MFA for root | Root uses virtual/passkey MFA (verify which) | 1 |
| IAM.18 (verify) | Support role exists (AWSSupportAccess) | Not created; cheap candidate for guardrails in Phase 3 | 0 candidate |

## Risk acceptance template

> **Risk:** _what can go wrong and which control is missing or failing (link threat model # / Security Hub control)._ **Owner:** _the named person accountable for the decision._ **Compensating control:** _what reduces the risk meanwhile (e.g. GuardDuty alert instead of a CIS metric alarm)._ **Expiry date:** _when this acceptance must be reviewed or the control implemented (max 90 days for Tier 1 items)._ **Approved by / date:** _name, date._
