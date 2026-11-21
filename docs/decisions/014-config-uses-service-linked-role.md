# ADR-014: Config uses the service-linked role

- **Status:** Accepted
- **Date:** 2026-11-18
- **Original question:** Q-n
- **Recommended by:** Not recorded (options presented by Claude)
- **Decided by:** David

## Context

Config needs an IAM role to read resource configurations.

## Options considered

1. The AWS service-linked role `AWSServiceRoleForConfig`.
2. A custom role.

## Decision

Option 1: the service-linked role, so there is nothing for us to over-broaden.

## Consequences

- Terraform creates the role explicitly (`aws_iam_service_linked_role`) because a fresh account does not have it until Config is first enabled.
- The role has no KMS permissions, so Config delivers to S3 as the `config.amazonaws.com` service principal. The Config key policy therefore grants that principal (with `aws:SourceAccount` and `aws:SourceArn`), not the role (troubleshooting #10).
- Deleting the role at teardown is asynchronous and may conflict while Config shuts down (unverified, see `evidence/teardown-proof.md`).

## Related

- [components/config.md](../components/config.md)
- [components/kms-config-key.md](../components/kms-config-key.md)
- [operations/troubleshooting.md](../operations/troubleshooting.md)
