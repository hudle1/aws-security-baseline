# Component: Account-level S3 Block Public Access

**Stack:** `infra/guardrails` · **Written:** Phase 3 · **Verified live:** 2026-11-16

## What it is

An account-wide switch that stops any S3 bucket in the account from being made public, regardless of individual bucket settings or ACLs. It applies to existing and future buckets.

## Why we have it

Threat addressed: a bucket (especially the CloudTrail log bucket, which holds a map of the account) becoming publicly readable through a bad ACL or bucket policy. See [threat-model.md](../threat-model.md) #3 (log bucket exposed) and #19 (guardrails destroyed, removing the backstop). The log bucket also gets its own bucket-level block in Phase 4, so the account-level setting is a second layer.

## Configuration

| Setting | Value | What it does / what goes wrong without it |
| --- | --- | --- |
| `block_public_acls` | `true` | Rejects requests that add a public ACL. Without it, someone can grant `AllUsers` access through an ACL. |
| `ignore_public_acls` | `true` | Ignores any public ACL that already exists. Without it, old public ACLs keep working. |
| `block_public_policy` | `true` | Rejects bucket policies that grant public access. Without it, a policy with `Principal: "*"` can be applied. |
| `restrict_public_buckets` | `true` | Limits access through an existing public policy to AWS service principals and authorized users in the account. Without it, an already-public policy keeps serving the world. |

All four are on. This overrides bucket-level settings, so no bucket can be public until this is deliberately changed.

## File that defines it

`infra/guardrails/main.tf`: resource `aws_s3_account_public_access_block.this`. Output: `s3_block_public_access` (`outputs.tf`).

## How to verify it works

```powershell
$acct = aws sts get-caller-identity --query Account --output text --profile sandbox-admin
aws s3control get-public-access-block --account-id $acct --profile sandbox-admin
```

Expected: `PublicAccessBlockConfiguration` with all four values `true`.

**Result on 2026-11-16 (after the first apply):** `BlockPublicAcls`, `IgnorePublicAcls`, `BlockPublicPolicy` and `RestrictPublicBuckets` all `true`.

## How to change it safely

Don't loosen it. If a bucket must be public (for example static website hosting), prefer CloudFront with origin access control over turning this off. If you must change it: branch, edit `main.tf`, plan, read the plan, record the risk acceptance using the template in [control-tiers.md](../control-tiers.md), and re-enable as soon as possible. Check first for buckets that depend on public access: attempts to make them public start failing immediately.

## What breaks if it's removed

Removing the resource (including `terraform destroy` of this stack) deletes the account-level block. Existing buckets keep only their own bucket-level settings; any bucket without one can be made public again. Security Hub S3.1 fails. The log bucket's own bucket-level block is then the only thing standing between it and a public policy.

## Cost

Free.

## Related controls

- Security Hub: S3.1
- CIS v5.0.0 2.1.4 ("S3 Block Public Access enabled"). Security Hub reports it as `S3.1` (account level, requirement 2.1.4.1) and `S3.8` (bucket level, 2.1.4.2), both PASSED; Prowler passes 2.1.4 too (checked 2026-11-20, [prowler-cis-v5.0-summary.md](../compliance/prowler-cis-v5.0-summary.md))
- SOC 2: CC6.1, CC6.6 (see [compliance-mapping.md](../compliance-mapping.md))
