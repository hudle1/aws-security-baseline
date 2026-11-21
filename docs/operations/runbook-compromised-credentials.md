# Runbook: suspected compromised AWS credentials

**One page. Read top to bottom, do not skip.** For the sandbox account only. Commands are PowerShell with `--profile sandbox-admin`; placeholders in `<ANGLE_BRACKETS>`. **Status: written from the repo's design and tested tools; not yet rehearsed as a drill (pending).** The two things that keep evidence safe: **do not run `destroy`** (the log bucket has `force_destroy = true`, so a destroy erases the audit trail) and **do not delete anything you cannot undo** until the evidence is saved.

## 0. Is this real? Triggers

- A `[SECURITY ALERT]` email (all share one subject: **expand the Gmail thread**, [troubleshooting #19](troubleshooting.md)): CloudTrail `StopLogging`/`DeleteTrail`/`UpdateTrail`, KMS `ScheduleKeyDeletion`/`DisableKey`/`PutKeyPolicy`, log-bucket policy or versioning change, Config recorder stopped, GuardDuty severity 7 or higher, Access Analyzer finding.
- The $10 budget alarm, an AWS abuse or security notice (it goes to the security contact), a login you did not make.
- **If you caused it** (a test, a deploy), say so in the incident log and stop. Alerts also fire on your own `apply` ([components/alerts.md](../components/alerts.md)).

## 1. Confirm: who did what (5 minutes)

Every alert carries a CloudTrail event ID. Look it up (add `--region` for the event's region):

```powershell
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventId,AttributeValue=<EVENT_ID> --profile sandbox-admin --region us-east-1
```

Read `userIdentity` (who), `sourceIPAddress` and `userAgent` (from where), `eventName` and `requestParameters` (what). Expected: your SSO role from your own IP. Anything else: **treat as compromised and continue.**

## 2. Contain first (do these now, in this order)

1. **Cut the human session:** IAM Identity Center console, the user, revoke or delete active sessions and **disable the user** (console only; no CLI step used here). Then change the SSO password and re-register MFA.
2. **Long-lived keys should not exist.** Prove it: `aws iam list-users --profile sandbox-admin` should be empty, and `aws iam get-account-summary --profile sandbox-admin --query "SummaryMap.AccountAccessKeysPresent"` must be `0` (root keys). Any key found: `aws iam update-access-key --user-name <USER> --access-key-id <KEY_ID> --status Inactive`.
3. **Root:** if root may be involved (`ConsoleLogin` by root in CloudTrail, or GuardDuty root-use finding): change the root password, replace the MFA device, check no root access key was created. Root MFA is **virtual** and there is no hardware key yet ([ADR-019](../decisions/019-accept-virtual-root-mfa-for-v1.md)): a v1.1 item.
4. **Make sure the evidence survives:** `aws cloudtrail get-trail-status --name baseline-trail --profile sandbox-admin --region us-east-1` must say `IsLogging: true`. If not: `aws cloudtrail start-logging --name baseline-trail --profile sandbox-admin --region us-east-1`, and `aws configservice start-configuration-recorder --configuration-recorder-name baseline-recorder --profile sandbox-admin --region us-east-1`.

## 3. Scope: what did they change? (15 minutes)

Recent high-risk API calls in us-east-1 (IAM and other global events appear here; set `<UTC_START>` before the first suspicious event):

```powershell
foreach ($n in 'CreateUser','CreateAccessKey','AttachUserPolicy','PutUserPolicy','CreateRole','RunInstances','StopLogging','DeleteTrail','ScheduleKeyDeletion','PutBucketPolicy') { "== $n"; aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=$n --start-time <UTC_START> --max-results 10 --profile sandbox-admin --region us-east-1 --query "Events[].[EventTime,Username]" --output text }
```

**Other regions are logged but not alerted** (GuardDuty, Config and the alerts are us-east-1 only, [ADR-006](../decisions/006-detection-in-us-east-1-only.md)). Look for miners and stray resources everywhere:

```powershell
foreach ($r in ((aws ec2 describe-regions --query "Regions[].RegionName" --output text --profile sandbox-admin) -split "\s+")) { "$r : " + (aws ec2 describe-instances --region $r --profile sandbox-admin --query "length(Reservations[].Instances[])" --output text) }
```

Then run the repo's own checks: `.\scripts\verify.ps1` (35 controls; a failing row shows exactly what was weakened), GuardDuty (`aws guardduty list-findings`), Access Analyzer findings, Security Hub, and `.\make.ps1 plan-baseline` / `plan-guardrails` (any change here is drift made by hand, which may be the attacker).

## 4. Eradicate and recover

- Delete unknown IAM users, roles, keys and instances (list them first and save the details). Cancel a scheduled key deletion: `aws kms cancel-key-deletion --key-id <KEY_ID> --profile sandbox-admin --region us-east-1` (7-day window).
- Put tampered settings back **with Terraform**, not by hand: `.\make.ps1 plan-baseline`, read it, `.\make.ps1 apply-baseline`. Re-run `.\make.ps1 verify` until 35 of 35.
- Rotate anything the attacker could have read: the SNS alert email (is it still yours?), the security contact, SSO credentials.

## 5. Preserve evidence, then report

- Prove the logs were not altered: `aws cloudtrail validate-logs --trail-arn <TRAIL_ARN> --start-time <UTC_START>` (last result: [evidence/validate-logs-output.txt](../evidence/validate-logs-output.txt)).
- Save the event details from step 1 and 3 to a private file (not in git: they contain IPs and ARNs).
- If AWS reported abuse or a charge, reply to that case; use the `aws-support-access` role for support cases.
- Write a short incident note: timeline (UTC), root cause, what was changed, what detected it and how fast, what to improve.

## Limits of this runbook (say them out loud)

Detection is **detect-only**: a compromised admin can delete the alert rules, the topic or the trail, and prevention needs organization SCPs (Tier 2, [control-tiers.md](../control-tiers.md)). Alerts depend on the trail and EventBridge being up. Whether alerts still fire for calls made while the trail is stopped is untested ([components/alerts.md](../components/alerts.md)). There is no on-call: the alert goes to one mailbox.
