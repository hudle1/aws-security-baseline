# Security policy

## What this repository is

A portfolio project: Terraform for one personal AWS sandbox account. It is not a product and has no users beyond its author, but it is public, so it is written as if someone will read it closely. No real account IDs, ARNs, email addresses, keys or state files are committed; the examples use placeholders such as `<ACCOUNT_ID>` and `123456789012` (the AWS documentation example account).

## Reporting a problem

If you find a secret, a real account identifier, or a flaw in the controls or the CI workflow:

1. **Preferred:** use GitHub's private reporting: the repository's **Security** tab, **Report a vulnerability** (private vulnerability reporting is enabled for this repository, verified 2026-11-20).
2. **Otherwise:** open an issue that says only "security report, please contact me" and **do not put details, credentials or exploit steps in the issue**. The author will reply with a private channel.

Expect an acknowledgement within a week; this is a one-person project with no on-call. If you find a live credential, say so first: it must be revoked before anything else.

## What counts

In scope: leaked secrets or personal data in the repo or its history; a Terraform setting that weakens a documented control; a CI or supply-chain weakness (for example an unpinned action, a path filter on a required check, a broad token permission); an error in a doc that would lead someone to deploy something insecure.

Out of scope: the findings already documented as accepted risks in [docs/control-tiers.md](docs/control-tiers.md) (for example virtual root MFA, no S3 access logging); missing production features listed under "What I'd do in production" in the README; anything that needs access to the author's AWS account.

## How the repository protects itself

- **CI has no AWS credentials.** It runs static checks and mock-provider tests only ([docs/operations/ci.md](docs/operations/ci.md)).
- Workflow token is `contents: read`; every action is pinned to a full commit SHA; the trigger is `pull_request`, never `pull_request_target`.
- gitleaks scans the full history on every PR; push protection is on; the pre-commit hook runs gitleaks and `terraform fmt`.
- `main` is protected: a PR is required, and nine named status checks must pass with the branch up to date.
- GitHub-side: secret scanning with push protection, the dependency graph and Dependabot alerts, Dependabot version-update PRs (`.github/dependabot.yml`), and CodeQL default setup scanning the GitHub Actions workflows weekly. CodeQL is not yet a required check ([docs/operations/ci.md](docs/operations/ci.md)).
- No long-lived AWS keys anywhere: access is IAM Identity Center (SSO) with short-lived credentials.
- Terraform is pinned to the sandbox account (`allowed_account_ids`), and the scripts refuse to run if the SSO profile points at a different account.

## Supported versions

Only the current `main` branch.
