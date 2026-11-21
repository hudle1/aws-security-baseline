# Evidence: the Prowler scanner role is read-only

Prowler runs only with the `sandbox-audit` profile, an IAM Identity Center permission set that maps to the role `AWSReservedSSO_SecurityAuditReadOnly_<HASH>`. This page records why that is safe. Redacted: account ID, user name and the role-name hash.

## 1. What the role can do (read with the admin profile, read-only calls)

Checked 2026-11-20:

```powershell
aws iam list-attached-role-policies --role-name <ROLE_NAME> --profile sandbox-admin
aws iam list-role-policies --role-name <ROLE_NAME> --profile sandbox-admin
```

| Item | Result |
| --- | --- |
| Identity of the profile | `arn:aws:sts::<ACCOUNT_ID>:assumed-role/AWSReservedSSO_SecurityAuditReadOnly_<HASH>/<USER>` |
| Attached managed policies | **`SecurityAudit` only** |
| Inline policies | 0 |
| Permissions boundary | none |

**Gap to note:** the permission set was described as SecurityAudit + ViewOnlyAccess, but only `SecurityAudit` is attached to the role. If a Prowler check fails with an access error for a service outside SecurityAudit, attach the AWS managed policy `ViewOnlyAccess` to the permission set (read-only) and re-provision. Any check Prowler could not run is listed in the Prowler summary in `docs/compliance/`.

## 2. A write attempt is refused (reported by David, not re-run by Claude)

On 2026-11-20 David ran a `create-bucket` with `--profile sandbox-audit`. Result as reported: `AccessDenied`, "no identity-based policy allows s3:CreateBucket". This is the expected outcome for a role with only `SecurityAudit`, and matches section 1. It was deliberately not repeated, because repeating a write attempt with a scanner role proves nothing more and would create a bucket if the permissions were ever wrong.

## What this proves, and what it does not

- **Proves:** the scanner cannot create or change resources. A compromised or misbehaving scan tool can read configuration but not alter the account.
- **Does not prove:** that `SecurityAudit` reads nothing sensitive. It can read resource metadata and configuration (for example IAM policies and bucket settings), not S3 object contents.
