# Component: AWS Budget `monthly-10-usd`

**Stack:** `infra/guardrails` · **Written:** Phase 3 · **Verified live:** 2026-11-16

## What it is

A monthly cost budget of $10 that emails an alert when spend crosses thresholds. It existed as a manual budget before Terraform; we **imported** it (Terraform `import` block) instead of creating a second one, so there is no duplicate and no gap in alerting.

## Why we have it

Threat addressed: stolen credentials or a mistake running up cost (crypto mining, runaway resources). See [threat-model.md](../threat-model.md) #11. A budget is a cost signal, not a security control: alerts lag by hours, so GuardDuty `CryptoCurrency:*` findings are the faster detector.

## Configuration

| Setting | Value | Reason |
| --- | --- | --- |
| `name` | `monthly-10-usd` | Must match the existing budget exactly. A different name makes Terraform create a second budget. |
| `budget_type` | `COST` | Tracks dollars, not usage hours. |
| `limit_amount` / `limit_unit` | from `budget_limit_usd` (default 10) / `USD` | Variable so the limit can change without editing code. A string in the API, converted with `tostring()`. |
| `time_unit` | `MONTHLY` | Resets each calendar month. |
| `filter_expression` | `NOT RECORD_TYPE in [Credit, Refund]` | Gross spend: credits and refunds are excluded, so credits can't mask a compromise-driven cost spike. Without it, credits offset the measured spend and alerts fire later than real usage. |
| `metrics` | `["UnblendedCost"]` | The cost measure the budget uses. The provider requires it whenever `filter_expression` is set. Matches the live budget. |
| `billing_view_arn` | the account's `primary` billing view | Matches the live budget so the import doesn't change it. Built from `var.account_id`, never hard-coded. |
| Notification: 80% `ACTUAL` | email | Early warning at $8 of real spend. |
| Notification: 100% `ACTUAL` | email | Limit reached. |
| Notification: 100% `FORECASTED` | email | AWS predicts you will hit the limit before month end. May not fire on a new or very low-usage account because forecasts need usage history. |
| Subscriber | `budget_email` variable | Kept in the gitignored `guardrails.tfvars` and marked `sensitive`, so it isn't committed or shown in plan output. |

The pre-import budget had notifications at 100% actual, **85%** actual and 100% forecasted. Terraform replaces the 85% alert with the 80% one specified for this project.

**Credits/refunds filter (decided, Q-h in [design-decisions.md](../design-decisions.md)):** the live budget excludes `Credit` and `Refund` records, so it measures gross usage. The first Terraform draft had no matching block, so the plan would have removed the filter. It is now in code, along with `metrics` and `billing_view_arn`, so the import changes only the notifications and default tags. If the live budget is ever edited in the console, `terraform plan` will show the drift.

## File that defines it

`infra/guardrails/main.tf`: the `import` block and `aws_budgets_budget.monthly`. Variables: `budget_limit_usd`, `budget_email` (`variables.tf`). Example values: `guardrails.tfvars.example`. Output: `budget_name`.

## How to verify it works

```powershell
$acct = aws sts get-caller-identity --query Account --output text --profile sandbox-admin
aws budgets describe-budget --account-id $acct --budget-name monthly-10-usd --profile sandbox-admin
aws budgets describe-notifications-for-budget --account-id $acct --budget-name monthly-10-usd --profile sandbox-admin
```

Expected: `BudgetLimit` 10 USD, `TimeUnit` MONTHLY, and three notifications (80% ACTUAL, 100% ACTUAL, 100% FORECASTED).

**Result on 2026-11-16 (after the first apply):** limit 10.0 USD, `MONTHLY`, `Metrics` `UnblendedCost`, and the credits/refunds filter still present. Notifications were GREATER_THAN 80 ACTUAL, 100 ACTUAL and 100 FORECASTED; the old 85% alert is gone. The CLI shows `ThresholdType` as `null` because AWS's default is `PERCENTAGE`. The budget was imported, not recreated. Subscribers can be listed with `aws budgets describe-subscribers-for-notification` for each notification. Treat its output as private.

Terraform should report no changes after the first apply:

```powershell
$env:AWS_PROFILE = "sandbox-admin"
terraform plan "-var-file=guardrails.tfvars"
```

## How to change it safely

- **Limit:** change `budget_limit_usd` in `guardrails.tfvars`; plan shows an in-place update.
- **Thresholds:** edit the `notification` blocks; plan first.
- **Never** change `name`: it forces a replace (delete and create), which briefly leaves the account without a budget.
- The `import` block is only needed for the first apply. It is harmless to leave and can be removed afterwards.
- Read every plan line that mentions `notification` or `filter_expression`: the email is `sensitive` and hidden, so check the counts and thresholds you can see.

## What breaks if it's removed

`terraform destroy` of the guardrails stack deletes the real budget, and cost alerts stop silently. This is why guardrails is never destroyed for cost reasons (see [threat-model.md](../threat-model.md) #19); only `destroy-all` removes it.

## Cost

Expected $0 at this scale (one cost budget, no budget actions). Confirm against the AWS Budgets pricing page before adding budget actions or more budgets.

## Related controls

- CIS / Security Hub: none
- SOC 2: CC7.2, as an anomaly signal (see [compliance-mapping.md](../compliance-mapping.md))
