# Component: account quick wins (EBS encryption, security contact, support role, SSM sharing block)

**Stack:** `infra/guardrails` · **Written:** guardrails quick-wins PR (follow-up to Phase 5) · **Applied and verified live:** 2026-11-20 (all four settings read back from AWS; Security Hub re-evaluation still pending)

Four free account-level settings that fix four failing Security Hub controls found in the first Phase 5 scorecard (decision Q-r). All four are in `infra/guardrails/main.tf`, items 5 to 8. They are persistent and free, so they belong in the guardrails stack, not the billed baseline stack.

Current state before this change (read-only checks, 2026-11-20): EBS default encryption `False`; no security contact; `AWSSupportAccess` attached to nothing; SSM public sharing `Enable` (the default).

## EBS default encryption (Security Hub EC2.7)

1. **What it is:** `aws_ebs_encryption_by_default`, a per-region switch. Every new EBS volume and snapshot copy in us-east-1 is encrypted, using the AWS-managed key `aws/ebs` (free).
2. **Why:** an unencrypted volume holds data in the clear, and a leaked or shared snapshot of it is readable. The switch removes the chance of forgetting. Threat model: data exposure through snapshots (see [threat-model.md](../threat-model.md)); the sandbox has no EBS volumes today, so this is prevention.
3. **Configuration:** `enabled = true`. Reason: encrypting by default is the only setting that does not depend on every person remembering. Existing volumes are not changed.
4. **File:** `infra/guardrails/main.tf` (`aws_ebs_encryption_by_default.this`).
5. **Verify:** `aws ec2 get-ebs-encryption-by-default --region us-east-1 --profile sandbox-admin --query EbsEncryptionByDefault`. **Result on 2026-11-20:** `True`.
6. **Change safely:** turning it off does not decrypt anything but lets new volumes be unencrypted again. It applies to us-east-1 only; other regions keep their own setting.
7. **If removed:** new volumes can be created unencrypted; EC2.7 fails again.
8. **Cost:** free.
9. **Controls:** Security Hub EC2.7 (FSBP and CIS v5.0.0). SOC 2: CC6.1.

## Security contact (Security Hub Account.1)

1. **What it is:** `aws_account_alternate_contact` of type `SECURITY`. AWS sends security notices (abuse reports, compromised-credential warnings) to this contact.
2. **Why:** without it those notices can go to a stale billing mailbox. Early warning of a compromised key is one of the cheapest controls there is.
3. **Configuration:** name, email and phone come from three **sensitive** variables in `guardrails.tfvars` (gitignored); placeholders live in `guardrails.tfvars.example`. The title is a fixed, non-personal string because the provider requires one. No contact existed, so this creates one and nothing is imported.
4. **File:** `infra/guardrails/main.tf` (`aws_account_alternate_contact.security`), variables in `variables.tf`.
5. **Verify:** `aws account get-alternate-contact --alternate-contact-type SECURITY --profile sandbox-admin --query "AlternateContact.Name"`. **Result on 2026-11-20:** a contact exists with name, email and phone set and title `Security Contact` (values not recorded here by design).
6. **Change safely:** change the values in `guardrails.tfvars` and re-apply. Use a mailbox that is actually watched. Never commit real values: the variables are `sensitive`, but the tfvars file must stay gitignored.
7. **If removed:** AWS security notices have no dedicated recipient; Account.1 fails again.
8. **Cost:** free.
9. **Controls:** Security Hub Account.1 (FSBP and CIS v5.0.0). SOC 2: CC7.3, CC7.4.

## Support role (Security Hub IAM.18)

1. **What it is:** an IAM role `aws-support-access` with the AWS managed policy `AWSSupportAccess` and nothing else.
2. **Why:** CIS wants AWS Support handled through a dedicated role instead of the admin role (least privilege). The check passes when `AWSSupportAccess` is attached to a role.
3. **Configuration:** trust policy allows only principals **in this account** (`arn:aws:iam::<ACCOUNT_ID>:root`), so Access Analyzer sees no external access. No MFA condition on purpose: IAM Identity Center sessions do not carry `aws:MultiFactorAuthPresent`, so it would make the role impossible to assume; MFA is enforced at SSO login. One-hour sessions (`max_session_duration`).
4. **File:** `infra/guardrails/main.tf` (`aws_iam_role.support`, `aws_iam_role_policy_attachment.support`, `data.aws_iam_policy_document.support_trust`).
5. **Verify:** `aws iam list-entities-for-policy --policy-arn arn:aws:iam::aws:policy/AWSSupportAccess --profile sandbox-admin --query PolicyRoles[].RoleName`. **Result on 2026-11-20:** `aws-support-access`, with only `AWSSupportAccess` attached and no inline policies. About 3 minutes after creation Access Analyzer had raised **no finding** for the role (trust is same-account only).
6. **Change safely:** never attach other policies to it. Do not add external principals to the trust policy; that would create an Access Analyzer finding and trigger the `access-analyzer-active` alert.
7. **If removed:** IAM.18 fails again; nothing else depends on it.
8. **Cost:** free. (Opening support cases still depends on the account's support plan.)
9. **Controls:** Security Hub IAM.18 (CIS v5.0.0). SOC 2: CC6.3.

## Block public sharing of SSM documents (Security Hub SSM.7)

1. **What it is:** `aws_ssm_service_setting` for `/ssm/documents/console/public-sharing-permission`, set to `Disable`.
2. **Why:** by default an account may share Systems Manager documents with everyone. A document can contain commands, parameters and internal names, so a public one is an information leak. The control is rated CRITICAL because it is one click to expose.
3. **Configuration:** `setting_value = "Disable"`; the setting is addressed by its ARN, built from the account ID and region. No SSM documents exist, so nothing changes today.
4. **File:** `infra/guardrails/main.tf` (`aws_ssm_service_setting.block_public_document_sharing`).
5. **Verify:** `aws ssm get-service-setting --setting-id arn:aws:ssm:us-east-1:<ACCOUNT_ID>:servicesetting/ssm/documents/console/public-sharing-permission --region us-east-1 --profile sandbox-admin --query ServiceSetting.SettingValue`. **Result on 2026-11-20:** `Disable` (it was `Enable`, the default, before).
6. **Change safely:** only change it if you deliberately need to publish a document, and reset it afterwards. It is regional (us-east-1).
7. **If removed:** the setting returns to `Enable` (the default) and SSM.7 fails again.
8. **Cost:** free.
9. **Controls:** Security Hub SSM.7 (FSBP). SOC 2: CC6.1, CC6.6.

## Expected effect on the scorecard

When Security Hub re-evaluates, **4 of the 31 failed controls** (EC2.7, Account.1, IAM.18, SSM.7) should pass: 27 failures would remain, all documented in [control-tiers.md](../control-tiers.md).

**Status: not yet confirmed.** Checked a few minutes after the apply (2026-11-20), all four still showed `FAILED` with an update time from *before* the apply, so Security Hub had not re-evaluated them yet. Re-check later and record the real result here (and the final counts in Phase 7). Do not treat these four as passing until Security Hub says so.

**Terraform state:** `terraform plan` after the apply reports no changes.
