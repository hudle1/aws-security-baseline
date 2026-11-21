# ADR-016: The alerts SNS topic is encrypted with a customer-managed key

- **Status:** Accepted
- **Date:** 2026-11-18
- **Original question:** Q-p
- **Recommended by:** Claude (the finding below leaves no working alternative)
- **Decided by:** David

## Context

EventBridge cannot publish to an SNS topic encrypted with the AWS-managed `aws/sns` key, because that key's policy cannot be edited to grant EventBridge access (verified 2026-11-18 against the AWS Knowledge Center article "SNS not getting EventBridge notification" and the SNS key-management docs). A customer-managed key policy also must not use `aws:SourceAccount` / `aws:SourceArn` conditions for EventBridge delivery.

## Options considered

1. Customer-managed key (about $1/month).
2. `aws/sns` (does not work).
3. Unencrypted topic with a justified Checkov skip.

## Decision

Option 1: customer-managed key. Scoping to our rules is done in the topic policy (`aws:SourceArn` = our rule ARNs) instead of the key policy.

## Consequences

- About $1/month more. The key protects alert messages at rest inside SNS only, not the email path or the recipient's inbox.
- Alert text carries only event names, resource names, times and IDs, never secrets or the caller's identity.

## Related

- [components/alerts.md](../components/alerts.md)
- [components/kms-alerts-key.md](../components/kms-alerts-key.md)
