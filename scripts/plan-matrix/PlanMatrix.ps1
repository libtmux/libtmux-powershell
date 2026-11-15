<#
.SYNOPSIS
Plan the Linux CI matrix from matrix.json and the event, or check the jobs that finished.

.DESCRIPTION
`plan` prints the plan and, when asked, appends workflow outputs and a job
summary. `gate` reads the NEEDS environment variable, a `toJSON(needs)`
document, and exits 1 when a job that must have succeeded or been skipped did
not.

Scopes: `edges` runs the oldest and newest supported release on every
PowerShell version, and is the default for a push, a pull request and a
dispatch. `full` runs the whole table, tmux master and the refusal lanes, and is
what a Gallery release is bound to. `custom` runs only the tmux refs a dispatch
names.

.EXAMPLE
pwsh -NoLogo -NoProfile -File scripts/plan-matrix/PlanMatrix.ps1 plan -EventName push
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)] [ValidateSet('plan', 'gate')] [string] $Action = 'plan',
    [string] $Manifest = (Join-Path $PSScriptRoot 'matrix.json'),
    # github.event_name
    [string] $EventName = '',
    [string] $Scope = '',
    [string] $TmuxRef = '',
    [string] $Pwsh = '',
    [string] $Tmate = '',
    # The GITHUB_OUTPUT file.
    [string] $GithubOutput,
    # The GITHUB_STEP_SUMMARY file.
    [string] $Summary
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'PlanMatrix.psm1') -Force

if ($Action -ceq 'gate') {
    $json = if ($env:NEEDS) { $env:NEEDS } else { '{}' }
    $problems = @(Test-GateNeeds ($json | ConvertFrom-Json -AsHashtable))
    foreach ($problem in $problems) { [Console]::Error.WriteLine("gate: $problem") }
    exit [int] ($problems.Count -gt 0)
}

try {
    $plan = New-MatrixPlan -Manifest (Read-MatrixManifest $Manifest) -EventName $EventName -Scope $Scope `
        -TmuxRef $TmuxRef -Pwsh $Pwsh -Tmate $Tmate
} catch [InvalidOperationException] {
    [Console]::Error.WriteLine("plan: $($_.Exception.Message)")
    exit 1
}

ConvertTo-Json -InputObject $plan -Depth 6
$utf8 = [Text.UTF8Encoding]::new($false)
if ($GithubOutput) {
    $lines = (Get-PlanOutputs $plan).GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)`n" }
    [IO.File]::AppendAllText($GithubOutput, ($lines -join ''), $utf8)
}
if ($Summary) { [IO.File]::AppendAllText($Summary, (Get-PlanSummary $plan), $utf8) }
