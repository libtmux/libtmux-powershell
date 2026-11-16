<#
.SYNOPSIS
Install an official PowerShell release from the CI table.

.DESCRIPTION
Downloads powershell-<version>-<platform>.tar.gz from the PowerShell releases,
refuses it unless its SHA-256 is the one scripts/plan-matrix/matrix.json lists,
extracts it into the destination, and checks the installed pwsh reports the
version. The platform is linux-x64 unless -Platform names a macOS asset, whose
digest the caller gives with -Sha256 because the table lists only Linux. Run it
with the pwsh the runner already has.

.EXAMPLE
pwsh -NoLogo -NoProfile -File scripts/install-powershell/InstallPowerShell.ps1 -Version 7.4.20
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Version,
    [ValidateSet('linux-x64', 'osx-x64', 'osx-arm64')] [string] $Platform = 'linux-x64',
    [string] $Sha256,
    [string] $Destination = (Join-Path $(if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }) 'powershell'),
    [string] $Manifest = (Join-Path (Split-Path $PSScriptRoot) 'plan-matrix/matrix.json')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'InstallPowerShell.psm1') -Force

try {
    $pwsh = Install-PowerShellArchive -Version $Version -Manifest $Manifest -Destination $Destination `
        -Platform $Platform -Sha256 $Sha256
    Assert-PowerShellVersion $pwsh $Version
    "Installed PowerShell $Version at $pwsh"
} catch [InvalidOperationException] {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
