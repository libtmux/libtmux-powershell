<#
.SYNOPSIS
Check that a pull request is closed, then delete its documentation preview.

.DESCRIPTION
`eligibility` reads the pull request from the GitHub API with GH_TOKEN and
appends `should_cleanup=true` to the GITHUB_OUTPUT file when it is closed. It
writes `should_cleanup=false` first, so a failed check leaves the cleanup off.
A closed event can be rerun after the pull request reopens, which is why the
state is read again. `delete` removes the preview under the PowerShell prefix
of the docs bucket with the aws CLI. Either exits 1 when the pull request
number is not a positive integer.

.EXAMPLE
pwsh -NoLogo -NoProfile -File scripts/docs-preview-cleanup/DocsPreviewCleanup.ps1 `
    eligibility -Repository libtmux/libtmux-powershell -Pr 12 -GithubOutput $env:GITHUB_OUTPUT
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)] [ValidateSet('eligibility', 'delete')] [string] $Action,
    [Parameter(Mandatory)] [string] $Pr,
    # owner/name, for eligibility.
    [string] $Repository,
    # The GITHUB_OUTPUT file, for eligibility.
    [string] $GithubOutput,
    # The docs bucket, for delete.
    [string] $Bucket
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'DocsPreviewCleanup.psm1') -Force

try {
    if ($Action -ceq 'delete') {
        $prefix = Get-PreviewPrefix $Bucket $Pr
        & aws s3 rm $prefix --recursive
        exit $LASTEXITCODE
    }
    $utf8 = [Text.UTF8Encoding]::new($false)
    [IO.File]::AppendAllText($GithubOutput, "should_cleanup=false`n", $utf8)
    Assert-PullRequestNumber $Pr
    $response = & gh api --method GET "repos/$Repository/pulls/$Pr"
    if ($LASTEXITCODE) { exit $LASTEXITCODE }
    $eligible = Get-CleanupEligibility ($response -join "`n") $Pr
    [IO.File]::AppendAllText($GithubOutput, "should_cleanup=$($eligible.ToString().ToLowerInvariant())`n", $utf8)
} catch [InvalidOperationException] {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
