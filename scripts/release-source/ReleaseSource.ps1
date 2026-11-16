<#
.SYNOPSIS
Resolve the commit a Gallery release publishes and check the release tag.

.DESCRIPTION
Run it in a checkout of the commit being released. The tag is optional. A tag
must be named v0.1.N or v0.1.0-alphaN, be annotated, and point at -Commit. It
appends `commit=<sha>` to the GITHUB_OUTPUT file for the steps that publish
and exits 1 with the reason when a check fails.

.EXAMPLE
pwsh -NoLogo -NoProfile -File scripts/release-source/ReleaseSource.ps1 `
    -Tag v0.1.2 -Commit $env:GITHUB_SHA -GithubOutput $env:GITHUB_OUTPUT
#>
[CmdletBinding()]
param(
    [string] $Tag = '',
    [Parameter(Mandatory)] [string] $Commit,
    # The GITHUB_OUTPUT file.
    [Parameter(Mandatory)] [string] $GithubOutput
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'ReleaseSource.psm1') -Force

try {
    $source = Resolve-ReleaseSource -Commit $Commit -Tag $Tag
} catch [InvalidOperationException] {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
[IO.File]::AppendAllText($GithubOutput, "commit=$source`n", [Text.UTF8Encoding]::new($false))
"Release source $source"
