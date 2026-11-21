# Evidence: account-level Block Public Access stops a public bucket policy

**Date:** 2026-11-20 (MT), sandbox account. **Purpose:** show that the account-level setting (guardrails stack, [components/s3-block-public-access.md](../components/s3-block-public-access.md)) blocks a public bucket policy even when the bucket has no protection of its own. Redacted: account ID, SSO role name and user name.

## Method

A throwaway empty bucket was created, its own bucket-level Block Public Access was **deleted**, and a policy granting `s3:GetObject` to `Principal: "*"` was attached. With the bucket-level setting gone, only the account-level setting is left to stop it. Nothing was stored in the bucket, and the account-level setting was never changed. The bucket was deleted afterwards.

| Step | Command (PowerShell; `<BUCKET>` = `bpa-demo-e1b7918c`) | Result |
| --- | --- | --- |
| 1. Create bucket | `aws s3api create-bucket --bucket <BUCKET>` | OK |
| 2. Remove the bucket's own protection | `aws s3api delete-public-access-block --bucket <BUCKET>` | OK |
| 2b. Confirm it has none | `aws s3api get-public-access-block --bucket <BUCKET>` | `NoSuchPublicAccessBlockConfiguration`: the bucket has no setting of its own |
| 3. Attach a public-read policy | `aws s3api put-bucket-policy --bucket <BUCKET> --policy file://pubpol.json` | **Denied** (below) |
| 4. Confirm nothing attached | `aws s3api get-bucket-policy --bucket <BUCKET>` | `NoSuchBucketPolicy` |
| 5. Account setting unchanged | `aws s3control get-public-access-block --account-id <ACCOUNT_ID>` | all four flags `True` |
| 6. Clean up | `aws s3api delete-bucket --bucket <BUCKET>`, then `head-bucket` | delete OK; `head-bucket` fails: the bucket no longer exists |

The policy file (`pubpol.json`):

```json
{"Version":"2012-10-17","Statement":[{"Sid":"PublicRead","Effect":"Allow","Principal":"*","Action":"s3:GetObject","Resource":"arn:aws:s3:::<BUCKET>/*"}]}
```

## The denial (step 3), redacted

```text
An error occurred (AccessDenied) when calling the PutBucketPolicy operation: User: arn:aws:sts::<ACCOUNT_ID>:assumed-role/<SSO_ROLE>/<SSO_USER> is not authorized to perform: s3:PutBucketPolicy on resource: "arn:aws:s3:::<BUCKET>" because public policies are prevented by the BlockPublicPolicy setting in S3 Block Public Access.
```

## What this proves, and what it does not

- **Proves:** with the bucket unprotected, the account-level `BlockPublicPolicy` flag rejected the public policy, even for an administrator. That is the backstop for threat model #3 / #19: one mistaken bucket cannot be made public.
- **By elimination:** step 2b shows the bucket had no setting of its own, so the denial came from the account level. S3 does not name the level in the error message.
- **Does not prove** the other three flags (`BlockPublicAcls`, `IgnorePublicAcls`, `RestrictPublicBuckets`) by behavior; `verify.ps1` confirms all four are set, and the Terraform test confirms the code sets them.
- **Detect-only limit:** an administrator can still turn the account-level setting off. The Tier 1 alert covers the log bucket's policy, not this setting.

## CloudTrail record of the denied call

**Pending.** The denied `PutBucketPolicy` (and the `CreateBucket` and `DeleteBucket` around it) had not appeared in `lookup-events` about 35 minutes after the test, which is longer than usual. To be re-checked and recorded here, or the delay recorded as a finding. Do not treat the CloudTrail side as verified until then.
