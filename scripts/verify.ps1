<#
.SYNOPSIS
  Read-only verification of every control in both stacks (guardrails + baseline).

.DESCRIPTION
  Asks the live AWS account (through the AWS API) whether each control is really in
  the state the Terraform code asks for. Terraform tests (CI) prove the CODE requests
  the setting; this script proves AWS APPLIED it. It is test evidence and a demo.

  READ-ONLY: it only runs get-*, describe-*, list-* calls. It never creates, changes
  or deletes anything, so it is safe to run at any time.

  Safety interlock: it compares the account behind the SSO profile with the account_id
  in infra/baseline/baseline.tfvars (gitignored) and stops if they differ, so it can
  never report on the wrong account.

  Redaction: the 12-digit account ID (and any other 12-digit number) is replaced by
  <ACCOUNT_ID> in everything printed or saved. Personal details (security contact,
  alert email) are checked for existence but never printed.

  Exit code: 0 when every check passes, 1 when any check fails or errors.

.PARAMETER Profile
  AWS CLI profile. Default: sandbox-admin. (Needs read access; sandbox-audit also works
  for everything except account:GetAlternateContact if SecurityAudit lacks it.)

.PARAMETER Region
  Default us-east-1 (the only region both stacks use).

.PARAMETER TrailName
  Default baseline-trail (the default of var.trail_name).

.PARAMETER OutFile
  Optional. Also writes the redacted output to this file (UTF-8, no BOM).

.EXAMPLE
  .\scripts\verify.ps1 -OutFile docs\evidence\verify-output.txt
#>
[CmdletBinding()]
param(
    [string]$Profile = 'sandbox-admin',
    [string]$Region = 'us-east-1',
    [string]$TrailName = 'baseline-trail',
    [string]$OutFile
)

$ErrorActionPreference = 'Stop'
$script:Results = New-Object System.Collections.Generic.List[object]
$script:AccountId = $null

# --- helpers ---------------------------------------------------------------

# Replaces every 12-digit run with <ACCOUNT_ID>. Applied to ALL output.
function Protect-Text([string]$Text) {
    if ($null -eq $Text) { return '' }
    return ($Text -replace '\d{12}', '<ACCOUNT_ID>')
}

# Runs one AWS CLI call and returns the parsed JSON (or $null for empty output).
# No inline JSON arguments: PowerShell 5.1 strips quotes inside them (troubleshooting #13).
# stderr is discarded; a non-zero exit code becomes an exception with a short message.
function Invoke-Aws {
    param([Parameter(Mandatory)][string[]]$CliArgs)
    # Windows PowerShell 5.1 turns ANY native-command stderr into a terminating error
    # with an empty message when $ErrorActionPreference is 'Stop'. Relax it for this one
    # call and judge success by the exit code instead.
    $ErrorActionPreference = 'Continue'
    $out = & aws @CliArgs --profile $Profile --region $Region --output json --no-cli-pager 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw ("aws {0} failed (exit {1})" -f (($CliArgs | Select-Object -First 2) -join ' '), $LASTEXITCODE)
    }
    $text = ($out -join "`n")
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return ($text | ConvertFrom-Json)
}

# Runs one check. The script block must return @{ Pass = <bool>; Detail = <string> }.
# Any exception becomes a FAIL with the (redacted) error, so one broken check never
# hides the others.
function Test-Control {
    param([string]$Stack, [string]$Control, [scriptblock]$Check)
    try {
        $r = & $Check
        $pass = [bool]$r.Pass
        $detail = [string]$r.Detail
    }
    catch {
        $pass = $false
        $detail = 'ERROR: ' + $_.Exception.Message
    }
    $script:Results.Add([pscustomobject]@{
            Stack   = $Stack
            Control = $Control
            Result  = $(if ($pass) { 'PASS' } else { 'FAIL' })
            Detail  = (Protect-Text $detail)
        })
}

# --- 0. which account are we in? -------------------------------------------

$who = Invoke-Aws @('sts', 'get-caller-identity')
$script:AccountId = $who.Account

$tfvars = Join-Path $PSScriptRoot '..\infra\baseline\baseline.tfvars'
if (Test-Path $tfvars) {
    $m = Select-String -Path $tfvars -Pattern 'account_id\s*=\s*"(\d{12})"' | Select-Object -First 1
    if ($m -and $m.Matches[0].Groups[1].Value -ne $script:AccountId) {
        throw 'Profile account does not match account_id in baseline.tfvars. Stopping: wrong account.'
    }
    $accountNote = 'matches account_id in baseline.tfvars'
}
else {
    $accountNote = 'baseline.tfvars not found, account not cross-checked'
}
$acct = $script:AccountId

# --- GUARDRAILS stack ------------------------------------------------------

Test-Control 'guardrails' 'IAM password policy (CIS 1.7/1.8)' {
    $p = (Invoke-Aws @('iam', 'get-account-password-policy')).PasswordPolicy
    $ok = ($p.MinimumPasswordLength -ge 14) -and ($p.PasswordReusePrevention -ge 24) -and
    $p.RequireUppercaseCharacters -and $p.RequireLowercaseCharacters -and
    $p.RequireNumbers -and $p.RequireSymbols
    @{ Pass = $ok; Detail = "min length $($p.MinimumPasswordLength) (>=14), reuse $($p.PasswordReusePrevention) (>=24), upper/lower/number/symbol all required: $($p.RequireUppercaseCharacters -and $p.RequireLowercaseCharacters -and $p.RequireNumbers -and $p.RequireSymbols)" }
}

Test-Control 'guardrails' 'Account S3 Block Public Access (4 flags)' {
    $c = (Invoke-Aws @('s3control', 'get-public-access-block', '--account-id', $acct)).PublicAccessBlockConfiguration
    $ok = $c.BlockPublicAcls -and $c.IgnorePublicAcls -and $c.BlockPublicPolicy -and $c.RestrictPublicBuckets
    @{ Pass = $ok; Detail = "BlockPublicAcls=$($c.BlockPublicAcls) IgnorePublicAcls=$($c.IgnorePublicAcls) BlockPublicPolicy=$($c.BlockPublicPolicy) RestrictPublicBuckets=$($c.RestrictPublicBuckets)" }
}

Test-Control 'guardrails' 'IAM Access Analyzer (account zone of trust)' {
    $a = @((Invoke-Aws @('accessanalyzer', 'list-analyzers')).analyzers | Where-Object { $_.type -eq 'ACCOUNT' })
    $active = @($a | Where-Object { $_.status -eq 'ACTIVE' })
    @{ Pass = ($active.Count -ge 1); Detail = "$($active.Count) ACTIVE analyzer(s) of type ACCOUNT" }
}

Test-Control 'guardrails' 'Budget monthly-10-usd (limit + 3 notifications)' {
    $b = (Invoke-Aws @('budgets', 'describe-budget', '--account-id', $acct, '--budget-name', 'monthly-10-usd')).Budget
    $n = @((Invoke-Aws @('budgets', 'describe-notifications-for-budget', '--account-id', $acct, '--budget-name', 'monthly-10-usd')).Notifications)
    $forecast = @($n | Where-Object { $_.NotificationType -eq 'FORECASTED' }).Count
    $actual = @($n | Where-Object { $_.NotificationType -eq 'ACTUAL' }).Count
    $ok = ([double]$b.BudgetLimit.Amount -eq 10) -and ($actual -ge 2) -and ($forecast -ge 1)
    @{ Pass = $ok; Detail = "limit $($b.BudgetLimit.Amount) $($b.BudgetLimit.Unit)/$($b.TimeUnit), notifications: $actual actual + $forecast forecasted" }
}

Test-Control 'guardrails' 'EBS default encryption (EC2.7)' {
    $e = Invoke-Aws @('ec2', 'get-ebs-encryption-by-default')
    @{ Pass = [bool]$e.EbsEncryptionByDefault; Detail = "EbsEncryptionByDefault=$($e.EbsEncryptionByDefault)" }
}

Test-Control 'guardrails' 'Security contact set (Account.1)' {
    $c = (Invoke-Aws @('account', 'get-alternate-contact', '--alternate-contact-type', 'SECURITY')).AlternateContact
    # Existence only: name, email and phone are personal and are never printed.
    $ok = $c -and $c.EmailAddress -and $c.PhoneNumber -and $c.Name
    @{ Pass = [bool]$ok; Detail = 'SECURITY contact exists with name, email and phone (values not shown)' }
}

Test-Control 'guardrails' 'Support role with AWSSupportAccess (IAM.18)' {
    $null = Invoke-Aws @('iam', 'get-role', '--role-name', 'aws-support-access')
    $att = @((Invoke-Aws @('iam', 'list-attached-role-policies', '--role-name', 'aws-support-access')).AttachedPolicies)
    $has = @($att | Where-Object { $_.PolicyName -eq 'AWSSupportAccess' }).Count -ge 1
    @{ Pass = $has; Detail = "role exists; AWSSupportAccess attached: $has" }
}

Test-Control 'guardrails' 'SSM public document sharing blocked (SSM.7)' {
    $id = "arn:aws:ssm:${Region}:${acct}:servicesetting/ssm/documents/console/public-sharing-permission"
    $s = (Invoke-Aws @('ssm', 'get-service-setting', '--setting-id', $id)).ServiceSetting
    @{ Pass = ($s.SettingValue -eq 'Disable'); Detail = "SettingValue=$($s.SettingValue)" }
}

# --- BASELINE stack --------------------------------------------------------

$script:Trail = $null
$script:Bucket = $null
Test-Control 'baseline' 'CloudTrail exists, multi-region' {
    $t = @((Invoke-Aws @('cloudtrail', 'describe-trails', '--trail-name-list', $TrailName)).trailList)[0]
    if (-not $t) { return @{ Pass = $false; Detail = 'trail not found' } }
    $script:Trail = $t
    $script:Bucket = $t.S3BucketName
    @{ Pass = [bool]$t.IsMultiRegionTrail; Detail = "IsMultiRegionTrail=$($t.IsMultiRegionTrail), global service events=$($t.IncludeGlobalServiceEvents)" }
}

Test-Control 'baseline' 'CloudTrail is logging' {
    $s = Invoke-Aws @('cloudtrail', 'get-trail-status', '--name', $TrailName)
    @{ Pass = [bool]$s.IsLogging; Detail = "IsLogging=$($s.IsLogging), last delivery error: $(if ($s.LatestDeliveryError) { $s.LatestDeliveryError } else { 'none' })" }
}

Test-Control 'baseline' 'CloudTrail log file validation (CIS 3.2)' {
    @{ Pass = [bool]$script:Trail.LogFileValidationEnabled; Detail = "LogFileValidationEnabled=$($script:Trail.LogFileValidationEnabled)" }
}

Test-Control 'baseline' 'CloudTrail encrypted with KMS (CIS 3.5)' {
    @{ Pass = [bool]$script:Trail.KmsKeyId; Detail = $(if ($script:Trail.KmsKeyId) { 'KmsKeyId set (value not shown)' } else { 'no KMS key' }) }
}

Test-Control 'baseline' 'Log bucket: versioning Enabled' {
    $v = Invoke-Aws @('s3api', 'get-bucket-versioning', '--bucket', $script:Bucket)
    @{ Pass = ($v.Status -eq 'Enabled'); Detail = "Status=$($v.Status)" }
}

Test-Control 'baseline' 'Log bucket: Block Public Access (4 flags)' {
    $c = (Invoke-Aws @('s3api', 'get-public-access-block', '--bucket', $script:Bucket)).PublicAccessBlockConfiguration
    $ok = $c.BlockPublicAcls -and $c.IgnorePublicAcls -and $c.BlockPublicPolicy -and $c.RestrictPublicBuckets
    @{ Pass = $ok; Detail = "BlockPublicAcls=$($c.BlockPublicAcls) IgnorePublicAcls=$($c.IgnorePublicAcls) BlockPublicPolicy=$($c.BlockPublicPolicy) RestrictPublicBuckets=$($c.RestrictPublicBuckets)" }
}

Test-Control 'baseline' 'Log bucket: default encryption aws:kms' {
    $e = (Invoke-Aws @('s3api', 'get-bucket-encryption', '--bucket', $script:Bucket)).ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault
    @{ Pass = ($e.SSEAlgorithm -eq 'aws:kms'); Detail = "SSEAlgorithm=$($e.SSEAlgorithm)" }
}

Test-Control 'baseline' 'Log bucket: ACLs disabled (BucketOwnerEnforced)' {
    $o = (Invoke-Aws @('s3api', 'get-bucket-ownership-controls', '--bucket', $script:Bucket)).OwnershipControls.Rules[0]
    @{ Pass = ($o.ObjectOwnership -eq 'BucketOwnerEnforced'); Detail = "ObjectOwnership=$($o.ObjectOwnership)" }
}

Test-Control 'baseline' 'Log bucket: policy denies non-TLS requests' {
    $p = (Invoke-Aws @('s3api', 'get-bucket-policy', '--bucket', $script:Bucket)).Policy
    $doc = $p | ConvertFrom-Json
    $deny = @($doc.Statement | Where-Object { $_.Effect -eq 'Deny' -and ($_.Condition | ConvertTo-Json -Depth 6) -match 'aws:SecureTransport' }).Count -ge 1
    @{ Pass = $deny; Detail = "Deny statement on aws:SecureTransport=false present: $deny" }
}

foreach ($alias in 'baseline-cloudtrail', 'baseline-config', 'baseline-alerts') {
    $a = $alias
    Test-Control 'baseline' "KMS key rotation: alias/$a (CIS 3.6)" {
        # GetKeyRotationStatus rejects aliases (InvalidArnException), so resolve the alias to a key ID first.
        $keyId = (Invoke-Aws @('kms', 'describe-key', '--key-id', "alias/$a")).KeyMetadata.KeyId
        $r = Invoke-Aws @('kms', 'get-key-rotation-status', '--key-id', $keyId)
        @{ Pass = [bool]$r.KeyRotationEnabled; Detail = "KeyRotationEnabled=$($r.KeyRotationEnabled)" }
    }
}

Test-Control 'baseline' 'Config recorder: 7 required resource types' {
    $rec = @((Invoke-Aws @('configservice', 'describe-configuration-recorders')).ConfigurationRecorders)[0]
    $need = 'AWS::S3::Bucket', 'AWS::KMS::Key', 'AWS::CloudTrail::Trail', 'AWS::IAM::Role', 'AWS::IAM::Policy', 'AWS::IAM::User', 'AWS::IAM::Group'
    $have = @($rec.recordingGroup.resourceTypes)
    $missing = @($need | Where-Object { $have -notcontains $_ })
    @{ Pass = ($missing.Count -eq 0 -and $rec.recordingMode.recordingFrequency -eq 'CONTINUOUS'); Detail = "frequency=$($rec.recordingMode.recordingFrequency), missing types: $(if ($missing.Count) { $missing -join ', ' } else { 'none' })" }
}

Test-Control 'baseline' 'Config recorder is recording' {
    $s = @((Invoke-Aws @('configservice', 'describe-configuration-recorder-status')).ConfigurationRecordersStatus)[0]
    @{ Pass = ([bool]$s.recording -and $s.lastStatus -eq 'SUCCESS'); Detail = "recording=$($s.recording), lastStatus=$($s.lastStatus)" }
}

Test-Control 'baseline' 'Config delivers to the log bucket' {
    $d = @((Invoke-Aws @('configservice', 'describe-delivery-channel-status')).DeliveryChannelsStatus)[0]
    @{ Pass = ($d.configHistoryDeliveryInfo.lastStatus -eq 'SUCCESS'); Detail = "history delivery lastStatus=$($d.configHistoryDeliveryInfo.lastStatus)" }
}

Test-Control 'baseline' 'GuardDuty detector enabled' {
    $id = @((Invoke-Aws @('guardduty', 'list-detectors')).DetectorIds)[0]
    if (-not $id) { return @{ Pass = $false; Detail = 'no detector' } }
    $script:Detector = Invoke-Aws @('guardduty', 'get-detector', '--detector-id', $id)
    @{ Pass = ($script:Detector.Status -eq 'ENABLED'); Detail = "Status=$($script:Detector.Status), publishing=$($script:Detector.FindingPublishingFrequency)" }
}

Test-Control 'baseline' 'GuardDuty S3 Protection ENABLED' {
    $f = @($script:Detector.Features | Where-Object { $_.Name -eq 'S3_DATA_EVENTS' })[0]
    @{ Pass = ($f.Status -eq 'ENABLED'); Detail = "S3_DATA_EVENTS=$($f.Status)" }
}

Test-Control 'baseline' 'Security Hub: FSBP standard READY' {
    $s = @((Invoke-Aws @('securityhub', 'get-enabled-standards')).StandardsSubscriptions | Where-Object { $_.StandardsArn -match 'aws-foundational-security-best-practices' })[0]
    @{ Pass = ($s.StandardsStatus -eq 'READY'); Detail = "StandardsStatus=$($s.StandardsStatus)" }
}

Test-Control 'baseline' 'Security Hub: CIS v5.0.0 standard READY' {
    $s = @((Invoke-Aws @('securityhub', 'get-enabled-standards')).StandardsSubscriptions | Where-Object { $_.StandardsArn -match 'cis-aws-foundations-benchmark/v/5\.0\.0' })[0]
    @{ Pass = ($s.StandardsStatus -eq 'READY'); Detail = "StandardsStatus=$($s.StandardsStatus)" }
}

Test-Control 'baseline' 'SNS alert topic: subscription confirmed' {
    $arn = "arn:aws:sns:${Region}:${acct}:baseline-security-alerts"
    $a = (Invoke-Aws @('sns', 'get-topic-attributes', '--topic-arn', $arn)).Attributes
    @{ Pass = ([int]$a.SubscriptionsConfirmed -ge 1 -and [int]$a.SubscriptionsPending -eq 0); Detail = "confirmed=$($a.SubscriptionsConfirmed), pending=$($a.SubscriptionsPending)" }
}

Test-Control 'baseline' 'SNS alert topic: encrypted with a CMK' {
    $arn = "arn:aws:sns:${Region}:${acct}:baseline-security-alerts"
    $a = (Invoke-Aws @('sns', 'get-topic-attributes', '--topic-arn', $arn)).Attributes
    @{ Pass = [bool]$a.KmsMasterKeyId; Detail = $(if ($a.KmsMasterKeyId) { 'KmsMasterKeyId set (value not shown)' } else { 'not encrypted' }) }
}

$rules = (Invoke-Aws @('events', 'list-rules', '--name-prefix', 'baseline-alert-')).Rules
foreach ($name in 'cloudtrail-tamper', 'kms-tamper', 'logbucket-tamper', 'config-tamper', 'guardduty-high', 'access-analyzer-active') {
    $n = $name
    Test-Control 'baseline' "Alert rule ENABLED: $n" {
        $r = @($rules | Where-Object { $_.Name -eq "baseline-alert-$n" })[0]
        @{ Pass = ($r -and $r.State -eq 'ENABLED'); Detail = $(if ($r) { "State=$($r.State)" } else { 'rule not found' }) }
    }
}

# --- report ----------------------------------------------------------------

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('aws-security-baseline: control verification (read-only)')
$lines.Add("Date (UTC): $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss'))   Region: $Region   Profile: $Profile")
$lines.Add("Account: <ACCOUNT_ID> ($accountNote)")
$lines.Add('')
foreach ($stack in 'guardrails', 'baseline') {
    $rows = @($script:Results | Where-Object { $_.Stack -eq $stack })
    $lines.Add("== $stack stack: $(@($rows | Where-Object { $_.Result -eq 'PASS' }).Count) of $($rows.Count) passed")
    $lines.Add((($rows | Select-Object Result, Control, Detail | Format-Table -AutoSize -Wrap | Out-String -Width 220).TrimEnd()))
    $lines.Add('')
}
$total = $script:Results.Count
$passed = @($script:Results | Where-Object { $_.Result -eq 'PASS' }).Count
$lines.Add("TOTAL: $passed of $total passed")
$report = Protect-Text ($lines -join "`r`n")

Write-Output $report
if ($OutFile) {
    $dir = Split-Path -Parent $OutFile
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $full = if ([IO.Path]::IsPathRooted($OutFile)) { $OutFile } else { Join-Path (Get-Location) $OutFile }
    [IO.File]::WriteAllText($full, $report + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
}
if ($passed -ne $total) { exit 1 } else { exit 0 }
