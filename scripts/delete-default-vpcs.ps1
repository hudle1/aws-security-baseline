<#
.SYNOPSIS
  Deletes the DEFAULT VPC in every enabled region of the sandbox account (decision Q-t).
  Dry-run by default: it only reports. Nothing is deleted unless you pass -Execute.

.DESCRIPTION
  Why: every region ships with a default VPC whose default security group and default
  network ACL are permissive and which has no flow logs. Nothing in this project uses
  them (CIS 3.7, 5.2, 5.5 fail on them). Deleting them removes the exposure at the root
  and is free.

  Safety rules, applied in BOTH modes (the dry-run shows exactly what -Execute would do):
   1. The account behind the profile must match account_id in infra/baseline/baseline.tfvars.
   2. A default VPC is deleted only if it has NO network interfaces (ENIs), NO instances
      (anything not terminated), NO NAT gateways, NO VPC endpoints, and NO custom security
      groups, route tables or network ACLs. If any exist, the VPC is SKIPPED and the
      reason is printed: somebody used it, so a human decides.
   3. Only the VPC where IsDefault = true is ever touched.
   4. -Execute re-checks every rule immediately before each deletion.

  Deletion order (a VPC cannot be deleted while it has dependencies): detach and delete
  the internet gateway, delete the subnets, then delete the VPC (its default security
  group, default route table and default network ACL are removed with it).

  How to RESTORE a deleted default VPC (free, takes seconds, one per region):
    aws ec2 create-default-vpc --region <REGION> --profile sandbox-admin
  It is recreated with new IDs, a default subnet in each availability zone and an
  internet gateway. The old VPC ID does not come back.

.PARAMETER Profile
  AWS CLI profile. Default sandbox-admin.

.PARAMETER Region
  Optional: limit to these regions (default: every region enabled for the account).

.PARAMETER Execute
  Actually delete. Without it, the script is read-only.

.EXAMPLE
  .\scripts\delete-default-vpcs.ps1                      # dry-run, all enabled regions
  .\scripts\delete-default-vpcs.ps1 -Execute             # delete, after you reviewed the dry-run
#>
[CmdletBinding()]
param(
    [string]$Profile = 'sandbox-admin',
    [string[]]$Region,
    [switch]$Execute
)

$ErrorActionPreference = 'Stop'

# Replaces any 12-digit number (account ID) in printed text.
function Protect-Text([string]$Text) { if ($null -eq $Text) { return '' }; return ($Text -replace '\d{12}', '<ACCOUNT_ID>') }

# One AWS CLI call -> parsed JSON (or $null). Same pattern as verify.ps1: stderr is
# discarded and a non-zero exit code becomes an exception (see troubleshooting #20).
function Invoke-Aws {
    param([Parameter(Mandatory)][string[]]$CliArgs, [string]$InRegion)
    $ErrorActionPreference = 'Continue'
    $extra = @('--profile', $Profile, '--output', 'json', '--no-cli-pager')
    if ($InRegion) { $extra += @('--region', $InRegion) }
    $out = & aws @CliArgs @extra 2>$null
    if ($LASTEXITCODE -ne 0) { throw ("aws {0} failed in {1} (exit {2})" -f (($CliArgs | Select-Object -First 2) -join ' '), $InRegion, $LASTEXITCODE) }
    $text = ($out -join "`n")
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return ($text | ConvertFrom-Json)
}

# --- 0. right account? ------------------------------------------------------
$acct = (Invoke-Aws @('sts', 'get-caller-identity') 'us-east-1').Account
$tfvars = Join-Path $PSScriptRoot '..\infra\baseline\baseline.tfvars'
if (-not (Test-Path $tfvars)) { throw 'baseline.tfvars not found: cannot confirm this is the sandbox account. Stopping.' }
$m = Select-String -Path $tfvars -Pattern 'account_id\s*=\s*"(\d{12})"' | Select-Object -First 1
if (-not $m -or $m.Matches[0].Groups[1].Value -ne $acct) { throw 'Profile account does not match account_id in baseline.tfvars. Stopping: wrong account.' }

# --- 1. which regions? ------------------------------------------------------
# describe-regions returns only regions ENABLED for this account (opt-in regions that
# were never enabled are not listed, and cannot hold resources).
if (-not $Region) { $Region = @((Invoke-Aws @('ec2', 'describe-regions') 'us-east-1').Regions | ForEach-Object { $_.RegionName } | Sort-Object) }

# --- 2. inspect each region's default VPC -----------------------------------
function Get-VpcReport([string]$R) {
    $vpcs = @((Invoke-Aws @('ec2', 'describe-vpcs', '--filters', 'Name=isDefault,Values=true') $R).Vpcs)
    if ($vpcs.Count -eq 0) { return [pscustomobject]@{ Region = $R; VpcId = ''; Subnets = 0; Enis = 0; Instances = 0; Nat = 0; Endpoints = 0; Custom = 0; Verdict = 'NO DEFAULT VPC'; Reason = 'nothing to do' } }
    $v = $vpcs[0].VpcId
    $f = @('--filters', "Name=vpc-id,Values=$v")
    $subnets = @((Invoke-Aws (@('ec2', 'describe-subnets') + $f) $R).Subnets).Count
    $enis = @((Invoke-Aws (@('ec2', 'describe-network-interfaces') + $f) $R).NetworkInterfaces).Count
    $inst = @((Invoke-Aws (@('ec2', 'describe-instances') + $f) $R).Reservations | ForEach-Object { $_.Instances } | Where-Object { $_.State.Name -ne 'terminated' }).Count
    # describe-nat-gateways is the one EC2 call whose flag is --filter (singular), not --filters.
    $nat = @((Invoke-Aws @('ec2', 'describe-nat-gateways', '--filter', "Name=vpc-id,Values=$v") $R).NatGateways | Where-Object { $_.State -notin 'deleted', 'failed' }).Count
    $ep = @((Invoke-Aws (@('ec2', 'describe-vpc-endpoints') + $f) $R).VpcEndpoints).Count
    $sg = @((Invoke-Aws (@('ec2', 'describe-security-groups') + $f) $R).SecurityGroups | Where-Object { $_.GroupName -ne 'default' }).Count
    $rt = @((Invoke-Aws (@('ec2', 'describe-route-tables') + $f) $R).RouteTables | Where-Object { -not ($_.Associations | Where-Object { $_.Main }) }).Count
    $acl = @((Invoke-Aws (@('ec2', 'describe-network-acls') + $f) $R).NetworkAcls | Where-Object { -not $_.IsDefault }).Count
    $custom = $sg + $rt + $acl
    $why = @()
    if ($enis) { $why += "$enis network interface(s)" }
    if ($inst) { $why += "$inst instance(s)" }
    if ($nat) { $why += "$nat NAT gateway(s)" }
    if ($ep) { $why += "$ep VPC endpoint(s)" }
    if ($custom) { $why += "$custom custom SG/route table/NACL" }
    $verdict = if ($why.Count) { 'SKIP' } else { 'SAFE TO DELETE' }
    $reason = if ($why.Count) { $why -join ', ' } else { 'no ENIs, instances, NAT gateways, endpoints or custom resources' }
    [pscustomobject]@{ Region = $R; VpcId = $v; Subnets = $subnets; Enis = $enis; Instances = $inst; Nat = $nat; Endpoints = $ep; Custom = $custom; Verdict = $verdict; Reason = $reason }
}

$report = foreach ($r in $Region) {
    try { Get-VpcReport $r }
    catch { [pscustomobject]@{ Region = $r; VpcId = ''; Subnets = 0; Enis = 0; Instances = 0; Nat = 0; Endpoints = 0; Custom = 0; Verdict = 'ERROR'; Reason = (Protect-Text $_.Exception.Message) } }
}

$mode = if ($Execute) { 'EXECUTE (deleting)' } else { 'DRY-RUN (read-only, nothing is deleted)' }
Write-Output "Default VPC cleanup: $mode"
Write-Output "Account: <ACCOUNT_ID> (matches baseline.tfvars)   Profile: $Profile   Regions checked: $(@($Region).Count)"
Write-Output ''
Write-Output (($report | Format-Table Region, VpcId, Subnets, Enis, Instances, Nat, Endpoints, Custom, Verdict -AutoSize | Out-String -Width 200).TrimEnd())
Write-Output ''
$safe = @($report | Where-Object Verdict -eq 'SAFE TO DELETE')
$skip = @($report | Where-Object Verdict -in 'SKIP', 'ERROR')
$none = @($report | Where-Object Verdict -eq 'NO DEFAULT VPC')
Write-Output ("Summary: {0} would be deleted, {1} skipped or errored, {2} regions already have no default VPC." -f $safe.Count, $skip.Count, $none.Count)
foreach ($s in $skip) { Write-Output ("  SKIP/ERROR {0} {1}: {2}" -f $s.Region, $s.VpcId, $s.Reason) }

if (-not $Execute) {
    Write-Output ''
    Write-Output 'Dry-run only. To delete the VPCs marked SAFE TO DELETE, run again with -Execute.'
    exit $(if ($skip.Count) { 1 } else { 0 })
}

# --- 3. delete (only SAFE regions, re-checked right before) -----------------
$failed = 0
foreach ($row in $safe) {
    $R = $row.Region
    $again = Get-VpcReport $R                       # rule 4: re-check immediately before deleting
    if ($again.Verdict -ne 'SAFE TO DELETE' -or $again.VpcId -ne $row.VpcId) { Write-Output "  $R : state changed since the check ($($again.Reason)); skipped"; $failed++; continue }
    try {
        $v = $row.VpcId
        $f = @('--filters', "Name=vpc-id,Values=$v")
        foreach ($igw in @((Invoke-Aws @('ec2', 'describe-internet-gateways', '--filters', "Name=attachment.vpc-id,Values=$v") $R).InternetGateways)) {
            $null = Invoke-Aws @('ec2', 'detach-internet-gateway', '--internet-gateway-id', $igw.InternetGatewayId, '--vpc-id', $v) $R
            $null = Invoke-Aws @('ec2', 'delete-internet-gateway', '--internet-gateway-id', $igw.InternetGatewayId) $R
        }
        foreach ($sn in @((Invoke-Aws (@('ec2', 'describe-subnets') + $f) $R).Subnets)) {
            $null = Invoke-Aws @('ec2', 'delete-subnet', '--subnet-id', $sn.SubnetId) $R
        }
        $null = Invoke-Aws @('ec2', 'delete-vpc', '--vpc-id', $v) $R
        Write-Output "  $R : deleted default VPC (internet gateway, subnets, VPC)"
    }
    catch { Write-Output ("  $R : FAILED: " + (Protect-Text $_.Exception.Message)); $failed++ }
}
Write-Output ''
Write-Output ("Done. {0} region(s) failed or changed state." -f $failed)
Write-Output 'To restore one: aws ec2 create-default-vpc --region <REGION> --profile sandbox-admin'
exit $(if ($failed) { 1 } else { 0 })
