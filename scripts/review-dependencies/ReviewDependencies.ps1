<#
.SYNOPSIS
Use one source-pinned CORE review build in an isolated CI checkout.

.DESCRIPTION
`version` prints a unique review version that extends the shared dependency pin.
`prepare` saves the committed locks as a baseline and rewrites the three shared
pins in Directory.Packages.props to that version. `verify` checks that the
rebuilt locks resolve the review version and differ from the baseline only in
the review packages' own hashes. The command runs in the checkout it belongs to.

.EXAMPLE
pwsh -NoLogo -NoProfile -File scripts/review-dependencies/ReviewDependencies.ps1 version -RunId 123 -Attempt 1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)] [ValidateSet('version', 'prepare', 'verify')] [string] $Action,
    [long] $RunId,
    [long] $Attempt,
    [string] $Version,
    [string] $Baseline
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'ReviewDependencies.psm1') -Force
$root = Split-Path (Split-Path $PSScriptRoot)

try {
    switch ($Action) {
        'version' {
            if (!$RunId -or !$Attempt) { throw [InvalidOperationException]::new('version needs -RunId and -Attempt') }
            Get-ReviewVersion -Root $root -RunId $RunId -Attempt $Attempt
        }
        'prepare' {
            if (!$Version -or !$Baseline) { throw [InvalidOperationException]::new('prepare needs -Version and -Baseline') }
            Initialize-ReviewPins -Root $root -Version $Version -Baseline $Baseline
        }
        'verify' {
            if (!$Version -or !$Baseline) { throw [InvalidOperationException]::new('verify needs -Version and -Baseline') }
            Test-ReviewLocks -Root $root -Version $Version -Baseline $Baseline
            'PASS CI dependency graph matches committed pins except reviewed package bytes'
        }
    }
} catch [InvalidOperationException] {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
