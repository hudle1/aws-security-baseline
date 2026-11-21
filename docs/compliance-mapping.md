# Compliance Mapping

How each v1 control **maps to** the CIS AWS Foundations Benchmark and SOC 2 Trust Services Criteria (CC6–CC8). A mapping shows which requirement a control supports. It is not a claim that the account or any organization is compliant: compliance is an auditor's judgment over policies, people, and evidence over time (see Gaps).

- **CIS version:** v5.0.0, the latest Security Hub supports (confirmed with `aws securityhub describe-standards`, 2026-11-15).
- **Control IDs:** Security Hub control IDs are used because they stay stable across CIS versions. CIS v5.0.0 has 40 controls in Security Hub; section numbers 3.1 to 3.6 below were **verified live on 2026-11-19** with `describe-standards-controls`. Other section numbers stay marked **verify** until checked in Phase 7.

## Control mapping

| v1 control | Security Hub control(s) | CIS requirement (v5.0.0 #: verify) | SOC 2 criteria |
| --- | --- | --- | --- |
| No root access keys; root MFA | IAM.4, IAM.9, IAM.6 (hardware MFA: expected fail, see control-tiers) | Root has no access keys; MFA on root | CC6.1, CC6.2 |
| SSO with MFA, no IAM users or access keys | IAM.? (verify user/key controls in v5) | MFA for console users; credentials rotated or unused removed | CC6.1, CC6.2, CC6.3 |
| IAM password policy | IAM.15 (length ≥ 14), IAM.16 (reuse prevention) | Password policy requirements | CC6.1 |
| IAM Access Analyzer (external access) | IAM.28 | Access Analyzer enabled (all regions: expected partial) | CC6.3, CC6.6 |
| Account-level S3 Block Public Access | S3.1 | S3 Block Public Access enabled | CC6.1, CC6.6 |
| Log bucket: bucket-level BPA, TLS-only policy, versioning | S3.8, S3.5 | Deny HTTP requests; block public access (bucket) | CC6.1, CC6.7 |
| Log bucket server access logging (not implemented) | CloudTrail.7 (**fails**; corrected 2026-11-19) | CIS v5.0.0 **3.4** (S3 access logging on the CloudTrail bucket). Tier 1 exception, see control-tiers.md. An earlier draft wrongly said it was not in v5.0.0 | CC7.2 |
| CloudTrail multi-region, management events | CloudTrail.1 | 3.1: CloudTrail enabled with a multi-Region trail and read/write management events | CC7.2, CC7.3 |
| CloudTrail KMS encryption | CloudTrail.2 | 3.5: CloudTrail encryption at rest | CC6.1, CC6.7 |
| CloudTrail log file validation | CloudTrail.4 | 3.2: Log file validation enabled | CC7.2 |
| KMS key rotation (CloudTrail, Config and alerts keys) | KMS.4 | 3.6: Rotation enabled for customer-managed keys | CC6.1 |
| AWS Config (limited types, continuous, service-linked role) | Config.1 (**fails**: limited types). 267 further controls cannot be evaluated for the same reason, see control-tiers.md | 3.3: AWS Config enabled with the service-linked role, recording all resources | CC7.1 |
| Config KMS key and delivery to the log bucket | KMS.4 | 3.6 (rotation) | CC6.1, CC6.7 |
| Security Hub (FSBP + CIS v5.0.0) | (the scorecard itself) | None of the 40 v5.0.0 controls is "Security Hub enabled"; it is the means of measuring them | CC7.1, CC7.2 |
| GuardDuty + S3 Protection | GuardDuty.1 (FSBP). GuardDuty.5, .6, .7, .8, .9, .11, .12, .13 **fail by design** (plans off, decision Q-o) | None in CIS v5.0.0 | CC6.8, CC7.2, CC7.3 |
| Real-time alerts (EventBridge + encrypted SNS, 6 rules) | (none: not a Security Hub control) | Partly. Security Hub's CIS v5.0.0 list has no CloudWatch metric-filter/alarm controls (verified 2026-11-19), but the benchmark text does (CIS 4.1 to 4.15, which Prowler reports as failing, see [prowler-cis-v5.0-summary.md](compliance/prowler-cis-v5.0-summary.md)). These EventBridge alerts cover the intent of 4.5, 4.7, 4.9 and, for the log bucket only, 4.8; they are not CloudWatch metric filters | CC7.2, CC7.3, CC7.4 |
| Budget alarm (actual + forecast) | (none) | (none) | CC7.2 (anomaly signal) |
| IR runbook: compromised credentials | (none, procedural) | (none) | CC7.3, CC7.4, CC7.5 |
| Change management: PRs, branch protection, plan review, CI static checks, no CI credentials | (none, process) | (none) | CC8.1, CC6.8 |

## SOC 2 criteria referenced

| Criterion | Summary |
| --- | --- |
| CC6.1 | Logical access security: identity, authentication, encryption of protected data |
| CC6.2 | Registering and authorizing users before access is granted |
| CC6.3 | Role-based access, least privilege, access removal |
| CC6.6 | Protection against threats from outside system boundaries |
| CC6.7 | Restricting transmission and movement of data (encryption in transit) |
| CC6.8 | Preventing or detecting unauthorized or malicious software |
| CC7.1 | Detecting configuration changes and vulnerabilities |
| CC7.2 | Monitoring components for anomalies indicating malicious acts or errors |
| CC7.3 | Evaluating security events to decide if they are incidents |
| CC7.4 | Responding to incidents |
| CC7.5 | Recovering from incidents |
| CC8.1 | Authorizing, testing, approving and implementing changes |

## Controls that fail by design

See [control-tiers.md](control-tiers.md#cis-controls-expected-to-fail-by-design) for every CIS control expected to fail in v1, with its tier and reason. They are a deliberate, documented gap, not an oversight.

## Gaps: what technical controls can't cover

A SOC 2 auditor would still need, and this repo does not provide:

- **Policies:** written information security, acceptable use, access control, change management, and incident response policies, approved and reviewed annually.
- **Access reviews:** periodic, evidenced reviews of who has access to what (Identity Center assignments, GitHub collaborators).
- **People controls:** security awareness training, background checks, onboarding/offboarding records.
- **Vendor management:** risk assessments of AWS, GitHub, HashiCorp and Anthropic as sub-processors.
- **IR testing:** a runbook exists (Tier 0); it hasn't been exercised in a tabletop or game day.
- **Evidence over time:** SOC 2 Type II tests controls over a period (usually 3–12 months). This sandbox is deployed for demos and torn down, so it produces point-in-time evidence only (`verify.ps1`, Prowler report, screenshots).
- **Risk assessment:** a formal, periodic risk assessment beyond this threat model, with risk acceptances signed by an owner.
