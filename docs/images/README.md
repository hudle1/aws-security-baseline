# Screenshots

Save screenshots **in this folder** as PNG, using the file names below, then uncomment the image line in the root [README](../../README.md) (the comment in the Demo section shows the syntax). **Take them before the baseline is destroyed** (planned 2026-11-28): the Security Hub scorecard and the GuardDuty finding only exist while the stack does.

## The shots

| File name | What to capture | Where | Why it earns its place |
| --- | --- | --- | --- |
| `security-hub-scorecard.png` | Security Hub **Summary** page: security score and the two enabled standards (FSBP and CIS v5.0.0) | Console, Security Hub, Summary | The posture scorecard in one image |
| `security-hub-cis-failed.png` | Security Hub, **Security standards**, CIS v5.0.0, filtered to **Failed** (5 controls) | Console, Security Hub, Security standards | Shows the failures are known and few |
| `verify-35-of-35.png` | Terminal after `.\scripts\verify.ps1`, showing the table and the `TOTAL: 35 of 35 passed` line | Windows Terminal | Proof the code and the live account agree |
| `alert-stoplogging-email.png` | The `[SECURITY ALERT] CloudTrail StopLogging ...` email, expanded in its Gmail thread | Gmail | The real-time alert, arrived within the minute |
| `guardduty-finding.png` | GuardDuty, **Findings**, with the archived filter showing `Stealth:IAMUser/CloudTrailLoggingDisabled` (severity Low) | Console, GuardDuty | The second detector, and its 22-minute delay |
| `bpa-denied.png` | Terminal showing the `AccessDenied ... BlockPublicPolicy` message from the demo, or the CloudTrail event for the denied `PutBucketPolicy` | Terminal or CloudTrail, Event history | Account-level Block Public Access working |
| `budget.png` | Budgets, `monthly-10-usd`, with its three alerts | Console, Billing, Budgets | The cost safety net |

Optional: the Prowler HTML report is not kept (raw output is deleted because it contains account IDs). If you want a screenshot of it, re-run the scan, redact it, and delete the raw output afterwards.

## How to redact (do this every time, before saving)

Anything that identifies the account or a person must be **covered with a solid box**, not blurred (blur can be partly reversed).

1. Take the shot with **Win + Shift + S** (Snipping Tool) and select only the part you need. Cropping out the top-right account menu removes most identifiers for free.
2. Open it in **Paint**, choose a solid black **rectangle** with fill, and cover:
   - the **12-digit account ID** (it appears in the console's account menu, in ARNs, in some URLs, and in some terminal lines);
   - your **name, email address and IAM Identity Center user name** (account menu, Gmail header, the `sandbox-admin` identity line);
   - **IP addresses**, **access key IDs**, **session or request IDs**, and the **random suffix of the log bucket name** if visible;
   - bucket names, ARNs and resource IDs you would not paste in public.
3. Terminal output from `verify.ps1` and the evidence files is already redacted by the script; still read it once.
4. **Save as PNG** to this folder. Open the saved file and look at it at full size to check nothing is left. Do **not** keep an unredacted copy in this repo or in a folder that syncs to it.
5. Check the file name and the image **metadata** (right-click, Properties, Details) for your name or path. Paint's "save as" normally keeps none; if in doubt, take a screenshot of the screenshot.
6. Run `gitleaks git --no-banner` before committing (the pre-commit hook does this too).

Never screenshot: the AWS access portal page with credentials, a "copy credentials" dialog, the root account sign-in, or anything with the alert email address in clear.
