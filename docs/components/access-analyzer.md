# Component: IAM Access Analyzer (external access)

**Stack:** `infra/guardrails` · **Written:** Phase 3 · **Verified live:** 2026-11-16 (accepted findings: 2026-11-20)

## What it is

A regional AWS service that analyzes resource policies (S3 buckets, KMS keys, IAM role trust policies, and others) and produces a **finding** whenever a resource is shared with something outside the "zone of trust". Ours is an **account-level** analyzer, so the zone of trust is this one AWS account: anything shared with another account, or publicly, is a finding.

## Why we have it

Threat addressed: unintended external access, such as a log bucket or KMS key policy opened to another account, or a role trusted by an outside principal. See [threat-model.md](../threat-model.md) #21 (resource shared outside the account), and the related #3 (log bucket exposure) and #5 (key policy changed to grant access to an attacker). It is a detective control: it detects after the fact and does not block anything.

## Configuration

| Setting | Value | Reason |
| --- | --- | --- |
| `analyzer_name` | `account-external-access` | Descriptive and stable; renaming forces replacement. |
| `type` | `ACCOUNT` | The external-access analyzer scoped to this account. The `ACCOUNT_UNUSED_ACCESS` types are a different, **paid** feature and are deliberately not used. |
| Region | `us-east-1` (from the provider) | Analyzers are regional. Resources in other regions are **not** analyzed. This is a known partial for the CIS check; see [control-tiers.md](../control-tiers.md). |

## File that defines it

`infra/guardrails/main.tf`: resource `aws_accessanalyzer_analyzer.account`. Output: `access_analyzer_name` (`outputs.tf`).

## How to verify it works

Analyzer exists and is active:

```powershell
aws accessanalyzer list-analyzers --type ACCOUNT --region us-east-1 --profile sandbox-admin --query "analyzers[].{name:name,status:status,type:type}"
```

Expected: `account-external-access`, status `ACTIVE`, type `ACCOUNT`.

**Result on 2026-11-16 (after the first apply):** exactly that, and the findings query returned an empty list (`[]`).

Current findings (empty is good on a fresh account):

```powershell
$arn = aws accessanalyzer list-analyzers --type ACCOUNT --region us-east-1 --profile sandbox-admin --query "analyzers[?name=='account-external-access'].arn | [0]" --output text
aws accessanalyzer list-findings-v2 --analyzer-arn $arn --region us-east-1 --profile sandbox-admin
```

## Accepted findings (archived individually, 2026-11-20)

Two findings existed on the first scan of the account (2026-11-17; their creation date is when the analyzer first looked, not when the roles were created). Both were investigated read-only (trust policy, permissions, CloudTrail `CreateRole` events) and judged **expected external access**. Each was archived **by its own finding ID**. No archive rule exists (`list-archive-rules` returns none), on purpose: a broad rule such as "archive everything on IAM roles" could silently hide a future malicious trust-policy change (threat model #21).

| Role | External principal | Access it grants | Why it is expected |
| --- | --- | --- | --- |
| `github-actions/iam-policy-guard-gha` | GitHub Actions OIDC provider (`token.actions.githubusercontent.com`) | Inline policy only: `access-analyzer:ValidatePolicy`, `CheckNoNewAccess`, `CheckAccessNotGranted`, limited to us-east-1. No attached policies | IAM Policy Guard's CI role (tags `Project=iam-policy-guard`, `ManagedBy=terraform`), created 2026-11-15 by Terraform in David's SSO admin session. Trust is pinned to one repository's pull requests (`sub`) and the `sts.amazonaws.com` audience (`aud`). It can only run policy checks. |
| `aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_...` | IAM Identity Center's SAML provider (`AWSSSO_..._DO_NOT_DELETE`) | `AdministratorAccess` | The role David signs in with (`sandbox-admin`). Created 2026-11-12 by the Identity Center service itself and managed by AWS. Trust requires `SAML:aud` = the AWS sign-in endpoint. |

**GitHub OIDC subject format (recorded from David, 2026-11-20):** the `sub` condition on the first role is `repo:<owner>@<owner-id>/<repo>@<repo-id>:pull_request`, which looks unusual next to GitHub's older default `repo:OWNER/REPO:pull_request`. It is GitHub's **immutable OIDC subject format**, used for repositories created after July 2026. David hit this while building IAM Policy Guard: the old format broke his first trust policy, and the role has worked since (Policy Guard's PR #7 demo). This was **not independently verified from this repo**; it is David's first-hand observation. It is not a misconfiguration.

**What happens if either trust policy changes:** because the findings were archived individually, a change that grants *new* access (a different principal, action or condition) should raise a **new ACTIVE finding**, which fires the `access-analyzer-active` alert ([alerts.md](alerts.md)). This is the AWS-documented behavior of archived findings, but it has **not been live-tested for these roles**: treat "a loosened trust policy always alerts" as expected, not proven. A test with a throwaway role (archive its finding, then change its trust, and check for a new finding and an email) is a good Phase 7 exercise.

**Review these two on a schedule.** An archived finding is invisible in the default view. Re-check them whenever Policy Guard's Terraform changes, and in every audit: confirm the trust policies still match the table above:

```powershell
aws iam get-role --role-name iam-policy-guard-gha --profile sandbox-admin --query "Role.AssumeRolePolicyDocument"
aws accessanalyzer list-findings-v2 --analyzer-arn <ANALYZER_ARN> --region us-east-1 --profile sandbox-admin --filter '{\"status\":{\"eq\":[\"ARCHIVED\"]}}' --query "findings[].[resource,resourceType,status]"
```

**Result on 2026-11-20:** both archived, 0 ACTIVE findings, 0 archive rules.

## How to change it safely

The analyzer has no tunable settings beyond name and type. To widen coverage to other regions, add another provider alias and analyzer per region (this raises the number of resources to manage; it is not planned for v1). Always run a plan first; a name or type change replaces the analyzer and drops its finding history. Review findings and archive only those you have judged intended, **one finding at a time, with a written reason** (see the table above). Never create an archive rule for a whole resource type.

## What breaks if it's removed

Nothing stops working. You lose visibility: external sharing of buckets, keys and roles goes unnoticed until someone looks. Security Hub IAM.28 fails.

## Cost

Free for the external-access analyzer. The first time one is created, AWS creates the service-linked role `AWSServiceRoleForAccessAnalyzer` automatically (no cost). Do not enable the unused-access analyzers without checking the pricing page first.

## Related controls

- Security Hub: IAM.28
- CIS: Access Analyzer enabled in all regions (expected partial, since ours is one region)
- SOC 2: CC6.3, CC6.6 (see [compliance-mapping.md](../compliance-mapping.md))
