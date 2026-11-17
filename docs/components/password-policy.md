# Component: IAM Account Password Policy

**Stack:** `infra/guardrails` · **Written:** Phase 3 · **Verified live:** 2026-11-16

## What it is

The account-wide rules AWS enforces on passwords for **IAM users**: minimum length, character classes, reuse history and expiry. There is exactly one password policy per AWS account.

## Why we have it

Threat addressed: weak or reused console passwords for IAM users, leading to account takeover. See [threat-model.md](../threat-model.md) #20 (weak or reused IAM user password). Honest scope note: this account's design uses SSO and no IAM users ([architecture.md](../architecture.md)), so the policy is **defense in depth** and exists mainly because CIS and Security Hub check for it. It does not govern the root user or SSO logins (those are governed by MFA and Identity Center settings).

## Configuration

| Setting | Value | Reason |
| --- | --- | --- |
| `minimum_password_length` | 20 | CIS v5.0.0 requires at least 14 (Security Hub IAM.15). IAM.7 accepts 8–128. 20 is a margin above the floor. |
| `password_reuse_prevention` | 24 | CIS v5.0.0 requires 24 (Security Hub IAM.16). IAM.7 accepts 12–24. Without it users can cycle back to an old, possibly leaked, password. |
| `require_uppercase_characters` / `require_lowercase_characters` / `require_numbers` / `require_symbols` | all `true` | IAM.7 defaults all four to true. Raises the search space for each character. |
| `allow_users_to_change_password` | `true` | Users can rotate their own password without an admin. Without it, a leaked password can only be fixed by an admin. |
| `max_password_age` | **unset** (never expires) | Deliberate. NIST SP 800-63B advises against forced periodic rotation (it pushes users toward weak, predictable passwords), CIS v5.0.0 doesn't require it, and IAM.7 passes without it. Checkov `CKV_AWS_9` (expects 90 days or less) is skipped in code with this reason. |

## File that defines it

`infra/guardrails/main.tf`: resource `aws_iam_account_password_policy.this`. Output: `password_policy_min_length` (`outputs.tf`).

## How to verify it works

```powershell
aws iam get-account-password-policy --profile sandbox-admin
```

Expected (key fields): `MinimumPasswordLength` 20, `PasswordReusePrevention` 24, all four `Require*` true, `AllowUsersToChangePassword` true, `ExpirePasswords` false.

**Result on 2026-11-16 (after the first apply):** exactly those values. A follow-up `terraform plan` reported "No changes".

Via Terraform, with no changes expected:

```powershell
$env:AWS_PROFILE = "sandbox-admin"
terraform plan "-var-file=guardrails.tfvars"
```

## How to change it safely

1. Edit the arguments in `main.tf` on a branch.
2. Run `terraform fmt`, `terraform validate`, then a plan, and read it. This resource is an account-wide singleton: apply overwrites the current policy.
3. Keep `minimum_password_length` at 14 or more and `password_reuse_prevention` at 24, or CIS-mapped checks (IAM.15, IAM.16) will fail.
4. Tightening affects users only when they next change their password; existing passwords keep working.

## What breaks if it's removed

`terraform destroy` on this resource **resets the account to the AWS default policy** (weak: short minimum length, no reuse prevention). Security Hub IAM.7, IAM.15 and IAM.16 then fail. Nothing stops working operationally, which is why the loss is easy to miss.

## Cost

Free.

## Related controls

- Security Hub: IAM.7, IAM.15, IAM.16
- CIS AWS Foundations v5.0.0: minimum length (§1.7) and reuse prevention (§1.8); section numbers per Cloudaware's v5.0.0 mapping, confirm against the enabled standard in Phase 5
- SOC 2: CC6.1 (see [compliance-mapping.md](../compliance-mapping.md))
