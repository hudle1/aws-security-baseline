# ADR-020: Delete the default VPC in every enabled region

- **Status:** Accepted (deletion pending approval of the dry-run output)
- **Date:** 2026-11-20
- **Original question:** Q-t
- **Recommended by:** Not recorded (options presented by Claude)
- **Decided by:** David

## Context

Prowler (with `--scan-unused-services`) fails CIS 3.7 (flow logs), 5.2 (default network ACL) and 5.5 (default security group) on the default VPC. Security Hub shows the same three as WARNING (not evaluated). In us-east-1 the default VPC has 0 network interfaces, and nothing in this project uses any default VPC.

## Options considered

1. Accept as Tier 1: free, but three visible failures remain.
2. Delete the default VPC (free; removes the findings and the permissive defaults at the root).
3. Enable flow logs and restrict the default NACL and security group (needs a log destination: cost and Terraform code for a VPC nothing uses).

## Decision

Option 2, extended to **all enabled regions** (17 default VPCs). Decided by David on 2026-11-20. `scripts/delete-default-vpcs.ps1` is dry-run by default and refuses to touch any VPC that has network interfaces, instances, NAT gateways, VPC endpoints or custom security groups, route tables or NACLs. The dry-run on 2026-11-20 found 17 default VPCs, all safe. **Status: deletion runs only after David approves the dry-run output.**

## Consequences

- Restore (free, seconds, per region): `aws ec2 create-default-vpc --region <REGION> --profile sandbox-admin`. The VPC comes back with new IDs, default subnets and an internet gateway.
- A later EC2 or Lambda-in-VPC experiment needs a VPC: restore the default one or create a purpose-built one in Terraform.
- How Security Hub and Prowler report CIS 3.7, 5.2 and 5.5 afterwards (passed, or "no resource") is unverified until re-run.
- The deletion is not managed by Terraform (default VPCs are not in state), so the script and this ADR are the record.

## Related

- [control-tiers.md](../control-tiers.md)
- [compliance/prowler-cis-v5.0-summary.md](../compliance/prowler-cis-v5.0-summary.md)
- [scripts/delete-default-vpcs.ps1](../../scripts/delete-default-vpcs.ps1)
