<#
.SYNOPSIS
Check downloaded packages against their evidence, and the tmux on PATH.

.DESCRIPTION
Reads package-evidence.json in the package directory and refuses the run unless
it lists at least one package and every listed file exists with the SHA-256 the
evidence records. With -ExpectedTmux it also refuses a PATH whose first tmux is
another executable.

.EXAMPLE
pwsh -NoLogo -NoProfile -File scripts/verify-package/VerifyPackage.ps1 -PackageRoot build/package
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $PackageRoot,
    [string] $ExpectedTmux
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'VerifyPackage.psm1') -Force

try {
    $files = @(Test-PackageBytes $PackageRoot)
    if ($ExpectedTmux) { Test-TmuxOnPath $ExpectedTmux }
    "PASS $($files.Count) package files match their evidence"
} catch [InvalidOperationException] {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
