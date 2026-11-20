# Component: AWS Config

**Stack:** `infra/baseline` · **Written:** Phase 5 · **Verified live:** 2026-11-19

## What it is

An AWS Config recorder (`baseline-recorder`) that records the configuration history of seven resource types and delivers it, encrypted with the [Config KMS key](kms-config-key.md), to the shared [log bucket](log-bucket.md) under `AWSLogs/<ACCOUNT_ID>/Config/`. It uses the AWS service-linked role `AWSServiceRoleForConfig` (decision Q-n) and records **continuously** (decision Q-m).

Recorded types: `AWS::S3::Bucket`, `AWS::KMS::Key`, `AWS::CloudTrail::Trail`, `AWS::IAM::Role`, `AWS::IAM::Policy`, `AWS::IAM::User`, `AWS::IAM::Group`. These are the types the threat model and the interview answers depend on.

## Why we have it

It answers "what did this resource look like before and after the change?", which CloudTrail alone does not. Threats in [threat-model.md](../threat-model.md): #7 (bucket policy tampering), #9 (recorder stopped), plus evidence for #4 and #5. **Security Hub also depends on it:** every control check is an AWS Config rule, and Security Hub needs the recorder running.

## Configuration

| Setting | Value | Reason |
| --- | --- | --- |
| `role_arn` | service-linked role (created explicitly by `aws_iam_service_linked_role`) | Decision Q-n: nothing for us to over-broaden. The role has **no KMS or S3 write permissions**, which is why delivery works through the service principal (see the key and bucket docs). |
| `recording_group` | `all_supported = false`, the seven types above | Cost and noise control for a one-person sandbox. Consequence below. |
| `recording_mode` | `CONTINUOUS` | Decision Q-m: a change is recorded within minutes; billed only on change ($0.003 per item) versus $0.012 per item for daily. Supports threat model #7. |
| Delivery channel prefix | none | With no prefix Config writes to `AWSLogs/<ACCOUNT_ID>/Config/`, the only prefix the bucket policy allows. A custom prefix would be denied. |
| Delivery channel key | `aws_kms_key.config` | Config files use the Config key, not the bucket default (decision b2). |
| Status | `is_enabled = true`, created after the delivery channel | A recorder that is not started records nothing; starting one with no channel is an error. |

### The cost of limited types: 267 unevaluated controls

Because only seven types are recorded, Security Hub reports **267 controls as `WARNING` with reason `CONFIG_RECORDER_MISSING_REQUIRED_RESOURCE_TYPES`** (checked 2026-11-19), and the control `Config.1` (CIS 3.3, FSBP) fails. In plain words: most of the FSBP/CIS scorecard is **not measured** rather than passed. That is the accepted price of the limited-types decision. The alternative, recording every supported type, raises the number of recorded items (and cost) with the resources in the account. See [control-tiers.md](../control-tiers.md).

## File that defines it

`infra/baseline/config.tf` (recorder, delivery channel, status). Key and role: `infra/baseline/kms-config.tf`. Bucket statements: `infra/baseline/log-bucket.tf` (`AWSConfigBucketPermissionsCheck`, `AWSConfigBucketExistenceCheck`, `AWSConfigBucketDelivery`). Checkov `CKV2_AWS_48` and `CKV2_AWS_45` are skipped on the recorder and status, with this reason.

## How to verify it works

```powershell
aws configservice describe-configuration-recorder-status --region us-east-1 --profile sandbox-admin --query "ConfigurationRecordersStatus[].{recording:recording,lastStatus:lastStatus}"
aws configservice describe-configuration-recorders --region us-east-1 --profile sandbox-admin --query "ConfigurationRecorders[].recordingGroup.resourceTypes"
```

**Result on 2026-11-19:** `recording: true`, `lastStatus: SUCCESS`, seven types as listed.

Does it record changes (live test, 2026-11-19): a temporary IAM role was created and deleted. Config recorded `ResourceDiscovered` about 60 seconds after creation and `ResourceDeleted` about 100 seconds after deletion:

```powershell
aws configservice get-resource-config-history --resource-type AWS::IAM::Role --resource-id <ROLE_ID> --region us-east-1 --profile sandbox-admin --query "configurationItems[].[configurationItemCaptureTime,configurationItemStatus]" --output text
```

## How to change it safely

1. Adding a type: add it to `resource_types`; it increases items billed. Adding types also moves some `WARNING` controls to evaluated.
2. Switching to daily recording changes decision Q-m and delays detection (and Security Hub results) by up to 24 hours; record it first.
3. Never stop the recorder to "fix" something: `StopConfigurationRecorder` triggers the `config-tamper` alert (see [alerts.md](alerts.md)).
4. Do not add a delivery prefix, and do not widen the bucket policy to `AWSLogs/<ACCOUNT_ID>/*`.

## What breaks if it's removed

Security Hub can no longer evaluate controls (they go to no-data), configuration history is lost, and the `config-tamper` alert has nothing to watch. Existing files in the bucket remain.

## Cost

$0.003 per configuration item when something changes; a sandbox with few changes is cents per month. Security Hub's control checks create Config rule evaluations (about $0.001 each). The Config key is about $1/month ([kms-config-key.md](kms-config-key.md)). **Estimate, to verify in Cost Explorer after a few days.**

## Related controls

- Security Hub: Config.1 (**fails by design**, limited types), see [control-tiers.md](../control-tiers.md).
- CIS v5.0.0: 3.3 (AWS Config enabled with the service-linked role).
- SOC 2: CC7.1, CC7.2 (see [compliance-mapping.md](../compliance-mapping.md)).
