<#
.SYNOPSIS
Check that the workflows follow the plan, the release gate and the shared-action rules.

.DESCRIPTION
Reads `.github/workflows/*.yml` as text and prints each problem. It exits 1 when
there is one. `ci.yml` must take its jobs from the plan and keep the names the
release gate expects; `release.yml` must call the CI at scope full from master;
no workflow may call apt-get or Python in a `run` line or set up Python; and a
libtmux/.github action must be pinned to a full commit SHA.

.EXAMPLE
pwsh -NoLogo -NoProfile -File scripts/check-workflows/CheckWorkflows.ps1
#>
[CmdletBinding()]
param([string] $Root = (Split-Path (Split-Path $PSScriptRoot)))

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'CheckWorkflows.psm1') -Force

$problems = @(Test-RepositoryWorkflows $Root)
foreach ($problem in $problems) { [Console]::Error.WriteLine($problem) }
if ($problems.Count) { exit 1 }
'PASS workflows follow the plan, the release gate and the shared-action rules'
