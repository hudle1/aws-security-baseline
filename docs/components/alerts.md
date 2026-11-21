# Component: real-time alerts (SNS + EventBridge)

**Stack:** `infra/baseline` · **Written:** Phase 5 · **Verified live:** 2026-11-18/19 MT (all six rules exercised and every email received; see [test results](#how-to-verify-it-works))

## What it is

Six EventBridge rules on the default bus in us-east-1 publish to one encrypted SNS topic (`baseline-security-alerts`), which emails the address in the sensitive variable `alert_email`. Each rule rewrites the raw event into one readable sentence with an input transformer.

| Rule | Fires on |
| --- | --- |
| `baseline-alert-cloudtrail-tamper` | CloudTrail `StopLogging`, `DeleteTrail`, `UpdateTrail` |
| `baseline-alert-kms-tamper` | KMS `ScheduleKeyDeletion`, `DisableKey`, `PutKeyPolicy` on **any** key in the account (decision Q-q) |
| `baseline-alert-logbucket-tamper` | S3 `PutBucketPolicy`, `DeleteBucketPolicy`, `PutBucketVersioning` on the log bucket |
| `baseline-alert-config-tamper` | Config `StopConfigurationRecorder`, `DeleteDeliveryChannel`, `DeleteConfigurationRecorder` |
| `baseline-alert-guardduty-high` | GuardDuty findings with severity >= 7 |
| `baseline-alert-access-analyzer-active` | IAM Access Analyzer findings with status `ACTIVE` |

## Why we have it

Without it, every detective control in this repo only helps if someone looks. Threats in [threat-model.md](../threat-model.md): #1 (trail stopped), #4 (KMS key deleted or disabled), #7 (bucket policy or Config recorder tampering), #8 and #9 (high-severity findings), #21 (resource shared outside the account). It is **detect-only**: it tells you, it does not stop anything.

## Configuration

| Setting | Value | Reason |
| --- | --- | --- |
| Topic encryption | customer-managed key `alias/baseline-alerts` | EventBridge cannot publish to a topic encrypted with the AWS-managed `aws/sns` key (decision Q-p). See [kms-alerts-key.md](kms-alerts-key.md). |
| Topic policy | `sns:Publish` allowed only to `events.amazonaws.com` with `aws:SourceArn` = our six rule ARNs; Deny non-TLS | **This is the publishing gate** (see trade-off below). |
| Subscription | email, endpoint = `var.alert_email` (sensitive, in gitignored `baseline.tfvars`) | The address never enters git. Terraform creates it as *pending*; the recipient must click the link. |
| Rule target | the topic, with `input_transformer` | Plain-English emails instead of raw event JSON. |
| KMS rule scope | any key in the account | Decision Q-q: never stale. Trade-off: harmless key work in the sandbox also alerts. |
| Retries / DLQ | EventBridge defaults, no dead-letter queue | A failed delivery is retried for up to 24h, then dropped. Metric `FailedInvocations` shows it. |

### SNS encryption scope

> SNS encryption scope: the customer-managed key protects alert messages at rest inside AWS (in SNS). It does not protect the email path or the recipient's inbox. Alert content must never include secrets, so input transformers carry only event names, resource names and IDs, times and severity.

Every template therefore carries only: event name, resource name or ID, time, region, severity, finding type or ID, and the CloudTrail event ID. It deliberately omits the caller's identity and source IP; to find out who did it, run the `lookup-events` command with the event ID that the email contains.

### Trade-off: no `aws:SourceAccount` on the key policy

The topic's KMS key policy allows `events.amazonaws.com` to `GenerateDataKey*` and `Decrypt` with **no** `aws:SourceAccount` or `aws:SourceArn` condition. AWS documents that those conditions break EventBridge delivery to an encrypted SNS topic ([SNS key management](https://docs.aws.eu/sns/latest/dg/sns-key-management.html), [Knowledge Center article](https://aws.amazon.com/premiumsupport/knowledge-center/sns-not-getting-eventbridge-notification/)). Decision (David, 2026-11-19): accept it. The **topic policy** (six rule ARNs) is the gate for who can publish. Residual risk: the events service principal could in theory use the key for another caller's request, but it could only encrypt or decrypt alert text, and the topic accepts publishes from nothing but our rules.

## File that defines it

`infra/baseline/alerts.tf` (topic, subscription, rules, targets, topic policy) and `infra/baseline/kms-alerts.tf` (key). The rule definitions live in one map, `local.alert_rules`; adding an alert is one new entry.

## How to verify it works

Subscription confirmed (a real ARN, not `PendingConfirmation`):

```powershell
aws sns list-subscriptions-by-topic --topic-arn <TOPIC_ARN> --region us-east-1 --profile sandbox-admin --query "Subscriptions[].SubscriptionArn"
```

Rules enabled:

```powershell
aws events list-rules --name-prefix baseline-alert- --region us-east-1 --profile sandbox-admin --query "Rules[].[Name,State]" --output text
```

Did a rule match and deliver (`TriggeredRules` and `Invocations` should be 1, `FailedInvocations` empty):

```powershell
aws cloudwatch get-metric-statistics --region us-east-1 --profile sandbox-admin --namespace AWS/Events --metric-name Invocations --dimensions Name=RuleName,Value=baseline-alert-cloudtrail-tamper --start-time <UTC_START> --end-time <UTC_END> --period 900 --statistics Sum
```

### Live test results (2026-11-19, sandbox)

| Rule | How it was exercised | EventBridge result | Email |
| --- | --- | --- | --- |
| `logbucket-tamper` | Real `PutBucketPolicy` calls from our own applies | matched | Received, text rendered correctly (David) |
| `kms-tamper` | Real `PutKeyPolicy` on the Config key (our apply) | matched | Received, text rendered correctly (David) |
| `guardduty-high` | `create-sample-findings` with `Backdoor:EC2/C&CActivity.B!DNS` (severity 8); sample archived | matched 1, delivered 1, 0 failed | **Received** at 11:53 PM MT on Nov 18 (David), the same minute as the event. Text: `[SECURITY ALERT] GuardDuty finding Backdoor:EC2/C&CActivity.B!DNS, severity 8, at 2026-11-19T06:53:48Z`, finding ID `cf97ad366d7d4655adb9dbf14312e3c8` (a sample finding). `CreateSampleFindings` logged at 11:53:47 PM MT. |
| `cloudtrail-tamper` | `StopLogging` then `StartLogging` immediately (about 2 seconds of gap) | matched 1, delivered 1, 0 failed | **Received** at 11:55 PM MT on Nov 18 (David), within the same minute as the event. Text: `[SECURITY ALERT] CloudTrail StopLogging on trail baseline-trail at 2026-11-19T06:55:56Z`, event ID `b82754c9-935e-48ad-a361-0be1fa84e1f7`. `StopLogging` logged at 11:55:56 PM MT. |
| `config-tamper` | `StopConfigurationRecorder` then `Start...` immediately (about 3 seconds) | matched 1, delivered 1, 0 failed | **Received** at 11:58 PM MT on Nov 18 (David), within the same minute as the event. Text: `[SECURITY ALERT] AWS Config StopConfigurationRecorder at 2026-11-19T06:58:16Z`, event ID `12be874c-c4fc-4d49-9117-6617a21b3653`. `StopConfigurationRecorder` logged at 11:58:16 PM MT. |
| `access-analyzer-active` | IAM role with a wildcard-principal trust policy limited by a random `sts:ExternalId`, no permission policies, deleted about 90 seconds later. I archived the finding; Access Analyzer then set it to `RESOLVED` itself when the role was gone (final state, checked 2026-11-20) | matched 1, delivered 1, 0 failed | **Received** at 11:50 PM MT on Nov 19 (David). Event time in the email 06:50:33Z, the same minute (mail timestamps have one-minute resolution, so the delay was at most about a minute). Text rendered correctly: `[SECURITY ALERT] Access Analyzer: ACTIVE external access finding on AWS::IAM::Role arn:aws:iam::<ACCOUNT_ID>:role/aa-alert-test-delete-me at 2026-11-20T06:50:33Z. Finding ID <FINDING_ID>.` |

Findings from the tests:

- **`StopLogging` itself triggers the alert, and the email arrives within a minute.** Proven end to end on 2026-11-18 (MT): `StopLogging` at 11:55:56 PM, EventBridge rule matched (TriggeredRules 1, Invocations 1, FailedInvocations 0), SNS published and delivered (0 failed), email in the inbox at 11:55 PM with event ID `b82754c9-...`. Stopping the trail does not silence its own alarm: the call is delivered to EventBridge as it takes effect. `StartLogging` a second later did not alert, as designed (the rule lists only stop, delete and update).
- **Gmail groups identical alerts into one conversation.** Every alert has the same subject, so a new alert can hide inside an old thread (on 2026-11-20 the three alerts above looked "missing" for this reason). Expand the thread to see them. See troubleshooting #19; a distinct subject per rule is a v1.1 item.
- **Access Analyzer was fast:** the finding appeared 74 seconds after the role was created, and the email arrived in the same minute as the finding (about 2 minutes after the role was created). The finding resolves itself once the resource is deleted, so archiving a test finding is unnecessary and a later `RESOLVED` overrides it.
- **GuardDuty is the slow backup, and rated Low.** `Stealth:IAMUser/CloudTrailLoggingDisabled` appeared about 22 minutes after the `StopLogging`, with **severity 2.0 (Low)**. The `guardduty-high` rule (>= 7) would therefore **never** have emailed it. The EventBridge `cloudtrail-tamper` rule is the alert that matters for a stopped trail.
- **SNS only delivers after the subscription is confirmed.** An event that fired before David clicked the link (a `PutBucketPolicy` at the first apply) produced no email. Expected behavior, not a fault.
- **Not tested:** whether API-call rules still fire for calls made *while* the trail is stopped. Only the `StopLogging` call itself was tested. Treat "alerts continue while the trail is off" as unproven.

## How to change it safely

1. Edit `local.alert_rules` in `alerts.tf`, then `terraform plan "-var-file=baseline.tfvars" "-out=baseline.tfplan"`. A new rule must be listed in the topic policy; that happens automatically because the policy iterates over all rules.
2. Keep every template to the allowed fields above. Never add the caller ARN, IP, user agent, request parameters or any value that could carry a secret.
3. Changing `alert_email` replaces the subscription; the new address must confirm before it receives anything.
4. Testing a rule: prefer a harmless real call (re-sending an existing setting) or GuardDuty sample findings. Never stop or delete a security control to "test it" for longer than a few seconds.

## What breaks if it's removed

Nothing stops working, but nobody hears about tampering in real time. Threat model #1, #4, #7, #8, #9 and #21 fall back to "detected only when someone looks".

## Limits (documented, not hidden)

- **us-east-1 only.** EventBridge rules only see events in the region where they are created (decision Q-f). Activity in other regions is logged by the multi-region trail but raises no alert here.
- **Detect-only.** A compromised admin can delete the rules or the topic. Prevention is an SCP (Tier 2).
- **GuardDuty and Access Analyzer rules fire only while those services are on.**
- **Delivery depends on one confirmed email address** and on EventBridge, SNS and your mail provider.

## Cost

EventBridge rules on AWS events and SNS email at this volume: about $0. The alerts key is about $1/month ([kms-alerts-key.md](kms-alerts-key.md)). **Estimate, to verify in Cost Explorer after a few days.**

## Related controls

- CIS v5.0.0: none required. Verified 2026-11-19 with `describe-standards-controls`: v5.0.0 has 40 controls and **none are CloudWatch metric-filter or alarm controls** (they were in CIS v1.2 to v3.0). These alerts are therefore a security improvement beyond the benchmark, not a CIS requirement.
- SOC 2: CC7.2, CC7.3, CC7.4 (see [compliance-mapping.md](../compliance-mapping.md)).
