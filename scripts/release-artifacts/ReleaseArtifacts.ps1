<#
.SYNOPSIS
Bind the release to the tested archives of the CI run it calls.

.DESCRIPTION
Reads the release run, its jobs and its artifacts from the GitHub API with
GH_TOKEN, requires the full-scope CI jobs to have succeeded at the release
commit, and writes a receipt that names the one `port-package` artifact. It
appends `artifact_id` to the GITHUB_OUTPUT file for the download step.

.EXAMPLE
pwsh -NoLogo -NoProfile -File scripts/release-artifacts/ReleaseArtifacts.ps1 `
    -RunId 123 -SourceCommit $env:GITHUB_SHA -Output receipt.json -GithubOutput $env:GITHUB_OUTPUT
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidateRange(1, [long]::MaxValue)] [long] $RunId,
    [Parameter(Mandatory)] [string] $SourceCommit,
    [Parameter(Mandatory)] [string] $Output,
    [Parameter(Mandatory)] [string] $GithubOutput
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'ReleaseArtifacts.psm1') -Force
if ($SourceCommit -cnotmatch '^[0-9a-f]{40}$') { throw 'The source commit must be a full lowercase SHA.' }

try {
    $run = Read-GitHubApi "actions/runs/$RunId"
    $attempt = $run['run_attempt']
    if (!(($attempt -is [int] -or $attempt -is [long]) -and $attempt -gt 0)) { throw 'CI run has no valid attempt' }
    $jobs = Read-GitHubApi "actions/runs/$RunId/attempts/$attempt/jobs?per_page=100"
    $artifacts = Read-GitHubApi "actions/runs/$RunId/artifacts?per_page=100"
    $receipt = New-ReleaseReceipt -Run $run -Jobs $jobs -Artifacts $artifacts -SourceCommit $SourceCommit -RunId $RunId
} catch [InvalidOperationException] {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
$null = New-Item -ItemType Directory -Path (Split-Path -Parent ([IO.Path]::GetFullPath($Output))) -Force
$utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($Output, (ConvertTo-Json -InputObject $receipt -Depth 6) + "`n", $utf8)
[IO.File]::AppendAllText($GithubOutput, "artifact_id=$($receipt.artifactId)`n", $utf8)
'PASS CI source, Linux gates and package artifact provenance'
