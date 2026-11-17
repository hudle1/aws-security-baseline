# Component: IAM Access Analyzer (external access)

**Stack:** `infra/guardrails` · **Written:** Phase 3 · **Verified live:** 2026-11-16

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

## How to change it safely

The analyzer has no tunable settings beyond name and type. To widen coverage to other regions, add another provider alias and analyzer per region (this raises the number of resources to manage; it is not planned for v1). Always run a plan first; a name or type change replaces the analyzer and drops its finding history. Review findings and archive only those you have judged intended, with a written reason.

## What breaks if it's removed

Nothing stops working. You lose visibility: external sharing of buckets, keys and roles goes unnoticed until someone looks. Security Hub IAM.28 fails.

## Cost

Free for the external-access analyzer. The first time one is created, AWS creates the service-linked role `AWSServiceRoleForAccessAnalyzer` automatically (no cost). Do not enable the unused-access analyzers without checking the pricing page first.

## Related controls

- Security Hub: IAM.28
- CIS: Access Analyzer enabled in all regions (expected partial, since ours is one region)
- SOC 2: CC6.3, CC6.6 (see [compliance-mapping.md](../compliance-mapping.md))
