<#
.SYNOPSIS
  Task runner for aws-security-baseline (GNU make is not installed on Windows).

.DESCRIPTION
  Usage:  .\make.ps1 <target>

  Read-only / local (safe any time):
    help               This list.
    fmt                terraform fmt -recursive (rewrites files to canonical format).
    validate           init -backend=false + validate, both stacks.
    test               terraform test (mock provider, no AWS calls), both stacks.
    lint               tflint and checkov, both stacks (needs both tools installed).
    check              fmt-check + validate + test + lint: the same checks CI runs.
    verify             scripts\verify.ps1 (read-only checks of the LIVE account).
    plan-guardrails    terraform plan for infra\guardrails (reads AWS, changes nothing).
    plan-baseline      terraform plan for infra\baseline (reads AWS, changes nothing).

  Changes AWS (each shows the plan and waits for you to type "yes"):
    apply-guardrails   Free, persistent stack (budget, password policy, S3 BPA, Access Analyzer, ...).
    apply-baseline     Billed stack (CloudTrail, KMS, bucket, GuardDuty, Security Hub, Config, alerts).
    deploy             apply-guardrails, then apply-baseline, then verify.
    destroy            Destroys the BASELINE stack only (plan -destroy first, then "yes").
    destroy-all        Destroys baseline, then guardrails. Extra confirmation: you must type destroy-all.

  Safety rules built in:
    - Never uses -auto-approve. Terraform always prints the plan and asks for "yes".
    - Always runs with AWS_PROFILE=sandbox-admin and confirms the account first: it stops
      if the profile's account differs from account_id in the stack's .tfvars file.
    - Needs infra\<stack>\<stack>.tfvars (copy the .tfvars.example next to it and fill it in).
#>
[CmdletBinding()]
param([Parameter(Position = 0)][string]$Target = 'help')

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$Stacks = @('guardrails', 'baseline')

function Write-Step([string]$Text) { Write-Host ''; Write-Host "==> $Text" -ForegroundColor Cyan }

# Runs a native command and stops the script if it fails (PowerShell does not do that by itself).
function Invoke-Native {
    param([Parameter(Mandatory)][string]$Exe, [string[]]$Arguments)
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Exe $($Arguments -join ' ') failed (exit code $LASTEXITCODE)" }
}

# checkov installed with pipx on Windows is exposed through a checkov.cmd shim that can fail with
# "File association not found for extension .py" (troubleshooting #22). Prefer the Python inside
# checkov's own pipx environment; fall back to whatever `checkov` is on PATH (CI uses pip).
function Invoke-Checkov([string[]]$Arguments) {
    $py = $null
    if (Get-Command pipx -ErrorAction SilentlyContinue) {
        $venvs = (& pipx environment --value PIPX_LOCAL_VENVS 2>$null)
        if ($venvs) { $cand = Join-Path $venvs 'checkov\Scripts\python.exe'; if (Test-Path $cand) { $py = $cand } }
    }
    if ($py) { Invoke-Native $py (@('-m', 'checkov.main') + $Arguments) } else { Invoke-Native checkov $Arguments }
}

function Get-StackDir([string]$Stack) { return (Join-Path $Root "infra\$Stack") }

# Pre-flight for anything that talks to AWS: profile, account match, tfvars present.
function Assert-Sandbox([string]$Stack) {
    $env:AWS_PROFILE = 'sandbox-admin'
    $tfvars = Join-Path (Get-StackDir $Stack) "$Stack.tfvars"
    if (-not (Test-Path $tfvars)) { throw "Missing $tfvars. Copy $Stack.tfvars.example to $Stack.tfvars and fill it in (the file is gitignored)." }
    $m = Select-String -Path $tfvars -Pattern 'account_id\s*=\s*"(\d{12})"' | Select-Object -First 1
    if (-not $m) { throw "account_id not found in $tfvars." }
    $expected = $m.Matches[0].Groups[1].Value
    $actual = (& aws sts get-caller-identity --query Account --output text 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'Not logged in. Run: aws sso login --profile sandbox-admin' }
    if ($actual -ne $expected) { throw "Profile sandbox-admin is in a different account than account_id in $Stack.tfvars. Stopping." }
    Write-Host "Account check OK: sandbox-admin matches $Stack.tfvars (ID not printed)." -ForegroundColor Green
}

function Initialize-Stack([string]$Stack, [switch]$NoBackend) {
    $dir = Get-StackDir $Stack
    $a = @("-chdir=$dir", 'init', '-input=false')
    if ($NoBackend) { $a += '-backend=false' }
    Invoke-Native terraform $a
}

function Invoke-Plan([string]$Stack) {
    Assert-Sandbox $Stack
    Initialize-Stack $Stack
    Write-Step "terraform plan: $Stack (read-only)"
    Invoke-Native terraform @("-chdir=$(Get-StackDir $Stack)", 'plan', "-var-file=$Stack.tfvars")
}

function Invoke-Apply([string]$Stack) {
    Assert-Sandbox $Stack
    Initialize-Stack $Stack
    Write-Step "terraform apply: $Stack. Read the plan, then type yes to continue or anything else to stop."
    # No -auto-approve: Terraform prints the plan and waits for "yes".
    Invoke-Native terraform @("-chdir=$(Get-StackDir $Stack)", 'apply', "-var-file=$Stack.tfvars")
}

function Invoke-Destroy([string]$Stack) {
    Assert-Sandbox $Stack
    Initialize-Stack $Stack
    Write-Step "terraform destroy: $Stack. Read what will be deleted, then type yes to continue or anything else to stop."
    Invoke-Native terraform @("-chdir=$(Get-StackDir $Stack)", 'destroy', "-var-file=$Stack.tfvars")
}

switch ($Target) {
    'help' { Get-Help $PSCommandPath -Detailed | Out-String | Write-Host }

    'fmt' { Write-Step 'terraform fmt -recursive'; Invoke-Native terraform @("-chdir=$Root", 'fmt', '-recursive') }

    'validate' {
        foreach ($s in $Stacks) {
            Write-Step "validate: $s"
            Initialize-Stack $s -NoBackend
            Invoke-Native terraform @("-chdir=$(Get-StackDir $s)", 'validate')
        }
    }

    'test' {
        foreach ($s in $Stacks) {
            Write-Step "terraform test: $s"
            Initialize-Stack $s -NoBackend
            Invoke-Native terraform @("-chdir=$(Get-StackDir $s)", 'test')
        }
    }

    'lint' {
        foreach ($tool in 'tflint', 'checkov') { if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool is not installed (see docs/operations/ci.md)." } }
        Write-Step 'tflint --init'
        Invoke-Native tflint @('--init', "--config=$Root\.tflint.hcl")
        foreach ($s in $Stacks) {
            Write-Step "tflint: $s"
            Invoke-Native tflint @("--chdir=$(Get-StackDir $s)", "--config=$Root\.tflint.hcl", '--format=compact')
        }
        Write-Step 'checkov'
        Invoke-Checkov @('-d', "$Root\infra", '--framework', 'terraform', '--compact', '--quiet')
    }

    'check' {
        Write-Step 'terraform fmt -check -recursive'
        Invoke-Native terraform @("-chdir=$Root", 'fmt', '-check', '-recursive', '-diff')
        & $PSCommandPath validate
        & $PSCommandPath test
        & $PSCommandPath lint
    }

    'verify' { Write-Step 'scripts\verify.ps1 (read-only)'; & (Join-Path $Root 'scripts\verify.ps1'); if ($LASTEXITCODE -ne 0) { throw 'verify.ps1 reported failures.' } }

    'plan-guardrails' { Invoke-Plan 'guardrails' }
    'plan-baseline' { Invoke-Plan 'baseline' }
    'apply-guardrails' { Invoke-Apply 'guardrails' }
    'apply-baseline' { Invoke-Apply 'baseline' }

    'deploy' {
        Invoke-Apply 'guardrails'
        Invoke-Apply 'baseline'
        Write-Host ''
        Write-Host 'Reminder: confirm the SNS subscription email, and allow about 20 minutes for the Security Hub standards (see docs/operations/deploy.md).' -ForegroundColor Yellow
        & $PSCommandPath verify
    }

    'destroy' { Invoke-Destroy 'baseline' }

    'destroy-all' {
        Write-Host 'destroy-all deletes the baseline stack (including the log bucket and every log in it) AND the guardrails stack (including the $10 budget).' -ForegroundColor Yellow
        $answer = Read-Host 'Type destroy-all to continue'
        if ($answer -ne 'destroy-all') { Write-Host 'Cancelled.'; exit 1 }
        Invoke-Destroy 'baseline'
        Invoke-Destroy 'guardrails'
    }

    default { throw "Unknown target '$Target'. Run: .\make.ps1 help" }
}
