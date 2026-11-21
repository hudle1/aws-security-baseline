# Evidence: the Prowler scanner role is read-only

Prowler runs only with the `sandbox-audit` profile, an IAM Identity Center permission set that maps to the role `AWSReservedSSO_SecurityAuditReadOnly_<HASH>`. This page records why that is safe. Redacted: account ID, user name and the role-name hash.

## 1. What the role can do (read with the admin profile, read-only calls)

Checked twice on 2026-11-20 (MT): before and after the permission set was re-provisioned in IAM Identity Center.

```powershell
aws iam list-attached-role-policies --role-name <ROLE_NAME> --profile sandbox-admin
aws iam list-role-policies --role-name <ROLE_NAME> --profile sandbox-admin
```

| Item | Before re-provisioning | After re-provisioning (current) |
| --- | --- | --- |
| Identity of the profile | `arn:aws:sts::<ACCOUNT_ID>:assumed-role/AWSReservedSSO_SecurityAuditReadOnly_<HASH>/<USER>` | same |
| Attached managed policies | `SecurityAudit` only | **`SecurityAudit` and `ViewOnlyAccess`** |
| Inline policies | 0 | 0 |
| Permissions boundary | none | none |

Adding a policy to a permission set does not reach the account's role until the permission set is re-provisioned; the first check, made right after the change, still showed only `SecurityAudit`. Both policies are AWS managed, read-only policies. Any check Prowler cannot run for lack of access is listed in the summary in `docs/compliance/`.

## 2. A write attempt is refused (reported by David, not re-run by Claude)

On 2026-11-20 David ran a `create-bucket` with `--profile sandbox-audit`. Result as reported: `AccessDenied`, "no identity-based policy allows s3:CreateBucket". This is the expected outcome for a role with only `SecurityAudit`, and matches section 1. It was deliberately not repeated, because repeating a write attempt with a scanner role proves nothing more and would create a bucket if the permissions were ever wrong.

## What this proves, and what it does not

- **Proves:** the scanner cannot create or change resources. A compromised or misbehaving scan tool can read configuration but not alter the account.
- **Does not prove:** that `SecurityAudit` reads nothing sensitive. It can read resource metadata and configuration (for example IAM policies and bucket settings), not S3 object contents.
