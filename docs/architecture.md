# Architecture

Terraform baseline for one personal AWS sandbox account, region `us-east-1`. Two root modules, split by **lifecycle and cost**, not as a security boundary (both share the same account and admin credentials).

| Stack | Contents | Cost | Lifecycle |
| --- | --- | --- | --- |
| `infra/guardrails` | Budget `monthly-10-usd` (imported), IAM password policy, account-level S3 Block Public Access, IAM Access Analyzer (external access) | Free | Persistent, never torn down for cost |
| `infra/baseline` | CloudTrail + 2 KMS keys + log-archive bucket, GuardDuty, Security Hub (FSBP + CIS), AWS Config | Billed | Deployed for demos, destroyed after |

## Diagram

```mermaid
flowchart LR
  subgraph LAPTOP["Trust boundary: David's laptop (IAM Identity Center SSO, MFA)"]
    DEV["David"]
    CC["Claude Code<br/>(permission rules: ask on apply/destroy/push)"]
    TF["Terraform CLI<br/>local state, gitignored"]
  end

  subgraph GH["Trust boundary: GitHub (no AWS credentials in v1)"]
    REPO["Repo hudle1/aws-security-baseline<br/>branch protection, push protection"]
    CI["Actions: fmt, validate, tflint, checkov, gitleaks"]
  end

  subgraph AWS["Trust boundary: AWS sandbox account"]
    subgraph G["infra/guardrails (free, persistent)"]
      BUD["Budget $10<br/>actual + forecast"]
      PWD["IAM password policy"]
      BPA["S3 Block Public Access<br/>(account level)"]
      IAA["IAM Access Analyzer<br/>(external access)"]
    end
    subgraph B["infra/baseline (billed, teardown)"]
      CT["CloudTrail<br/>multi-region, log validation"]
      KCT["KMS key: CloudTrail"]
      KCF["KMS key: Config"]
      S3["Log-archive bucket<br/>versioned, TLS-only"]
      CFG["AWS Config<br/>limited types, daily"]
      GD["GuardDuty<br/>+ S3 Protection"]
      SH["Security Hub<br/>FSBP + CIS"]
    end
  end

  DEV -->|"SSO short-lived creds"| TF
  CC -->|"runs plan; apply only after David approves"| TF
  TF -->|"AWS API calls"| G
  TF -->|"AWS API calls"| B
  DEV -->|"PR"| REPO --> CI

  CT -->|"cloudtrail.amazonaws.com<br/>AWSLogs/acct/CloudTrail/"| S3
  CFG -->|"config.amazonaws.com<br/>AWSLogs/acct/Config/"| S3
  KCT -.->|"encrypts"| CT
  KCF -.->|"encrypts"| CFG
  GD -->|"findings"| SH
  CFG -->|"evaluations for SH controls"| SH
  SH -->|"console review"| DEV
  BUD -->|"email alert"| DEV
  BPA -.->|"protects"| S3
  IAA -.->|"flags external access to"| S3
  IAA -->|"findings (when baseline deployed)"| SH
```

## Who writes to what

| Writer | Principal | Target | Scoped by |
| --- | --- | --- | --- |
| CloudTrail | `cloudtrail.amazonaws.com` | `s3://<bucket>/AWSLogs/<acct>/CloudTrail/` | Bucket policy: `aws:SourceArn` = this trail, `aws:SourceAccount`, `s3:x-amz-acl = bucket-owner-full-control` |
| CloudTrail | `cloudtrail.amazonaws.com` | CloudTrail KMS key | Key policy: `kms:EncryptionContext:aws:cloudtrail:arn`, `aws:SourceArn` |
| AWS Config | Config service role (assumed by `config.amazonaws.com`) | `s3://<bucket>/AWSLogs/<acct>/Config/` | Bucket policy: `aws:SourceAccount`; role policy limited to that prefix |
| AWS Config | Config service role | Config KMS key | Key policy: only the Config role, encrypt/generate data key |
| GuardDuty | GuardDuty service | Security Hub findings | Built-in integration; reads CloudTrail management events, VPC Flow Logs, DNS and S3 data events **independently** of our trail |
| Security Hub | Security Hub service-linked role | Config rules for its controls | Requires Config recording; controls on unrecorded resource types show "no data" |
| IAM Access Analyzer | Access Analyzer service-linked role | Findings (own console; Security Hub when deployed) | Reads resource policies only; account zone of trust |
| Terraform | David's SSO role | Both stacks | Human approval for every apply/destroy; `allowed_account_ids` pins the sandbox |

**Cross-stack dependency:** account-level S3 Block Public Access (guardrails) is a backstop for the log-archive bucket (baseline). The bucket also sets its own bucket-level BPA so it stays protected even if the account setting changes, but guardrails must never be destroyed to save cost.

## Deploy and teardown

```mermaid
flowchart LR
  A["sts get-caller-identity<br/>confirm sandbox"] --> B["guardrails: plan, review, apply<br/>(once)"]
  B --> C["baseline: plan, review, apply"]
  C --> D["scripts/verify.ps1<br/>API checks = evidence"]
  D --> E["make.ps1 destroy<br/>baseline only"]
  E --> F["make.ps1 destroy-all<br/>only if leaving AWS entirely"]
```

- Every `apply`/`destroy` shows a plan and waits for a human "yes". `-auto-approve` is denied in Claude Code settings.
- Teardown leaves two KMS keys in **pending deletion** (7-day window, not billed) and empties the versioned log bucket. Both are acceptable in a sandbox and wrong in production (see threat model).
- State is local and gitignored. Remote state (S3 + locking, separate account) is a production improvement.
