# Evidence: default VPCs deleted in all 17 enabled regions

**Date:** 2026-11-20 (MT) · **Decision:** [ADR-020](../decisions/020-delete-default-vpcs.md) · **Tool:** [scripts/delete-default-vpcs.ps1](../../scripts/delete-default-vpcs.ps1) · VPC IDs and the account ID are not shown.

Sequence: (1) a dry-run, read-only; (2) David approved the output; (3) the same script with `-Execute`, which re-checks every safety rule per region immediately before deleting; (4) a second dry-run to confirm none remain.

## What was checked, per region, before deleting

A default VPC is deleted only if it has **no network interfaces, no instances, no NAT gateways, no VPC endpoints and no custom security groups, route tables or network ACLs**. All 17 passed.

| Region | Subnets | Network interfaces | Instances | NAT gateways | Endpoints | Custom resources | Result |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| ap-northeast-1 | 3 | 0 | 0 | 0 | 0 | 0 | deleted |
| ap-northeast-2 | 4 | 0 | 0 | 0 | 0 | 0 | deleted |
| ap-northeast-3 | 3 | 0 | 0 | 0 | 0 | 0 | deleted |
| ap-south-1 | 3 | 0 | 0 | 0 | 0 | 0 | deleted |
| ap-southeast-1 | 3 | 0 | 0 | 0 | 0 | 0 | deleted |
| ap-southeast-2 | 3 | 0 | 0 | 0 | 0 | 0 | deleted |
| ca-central-1 | 3 | 0 | 0 | 0 | 0 | 0 | deleted |
| eu-central-1 | 3 | 0 | 0 | 0 | 0 | 0 | deleted |
| eu-north-1 | 3 | 0 | 0 | 0 | 0 | 0 | deleted |
| eu-west-1 | 3 | 0 | 0 | 0 | 0 | 0 | deleted |
| eu-west-2 | 4 | 0 | 0 | 0 | 0 | 0 | deleted |
| eu-west-3 | 3 | 0 | 0 | 0 | 0 | 0 | deleted |
| sa-east-1 | 3 | 0 | 0 | 0 | 0 | 0 | deleted |
| us-east-1 | 6 | 0 | 0 | 0 | 0 | 0 | deleted |
| us-east-2 | 3 | 0 | 0 | 0 | 0 | 0 | deleted |
| us-west-1 | 2 | 0 | 0 | 0 | 0 | 0 | deleted |
| us-west-2 | 4 | 0 | 0 | 0 | 0 | 0 | deleted |

Summary line of the executed run: `17 would be deleted, 0 skipped or errored`, then `Done. 0 region(s) failed or changed state.` (exit code 0).

## Confirmation that none remain

A second dry-run afterwards listed all 17 regions as `NO DEFAULT VPC` and its summary reported 17 regions already without a default VPC (exit code 0). This is an independent read-only check, not the deletion script's own success messages.

## First dry-run failed closed

The first dry-run marked every region `ERROR` because of a wrong CLI flag (`describe-nat-gateways` takes `--filter`, singular), so nothing could be marked safe. See [troubleshooting #23](../operations/troubleshooting.md).

## How to restore

```powershell
aws ec2 create-default-vpc --region <REGION> --profile sandbox-admin
```

Free, takes seconds, one per region. It comes back with new IDs, a default subnet in each availability zone and an internet gateway.

## Not yet verified

How Security Hub and Prowler report CIS 3.7 (flow logs), 5.2 (default NACL) and 5.5 (default security group) after the deletion: pending a re-run. Do not assume they now show PASS; they may show "no resource".
