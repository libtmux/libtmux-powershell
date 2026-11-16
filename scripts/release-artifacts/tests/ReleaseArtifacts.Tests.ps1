# Proves a release binds only to a trusted, complete, same-source CI run, and
# that each way the proof can fail is refused.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../ReleaseArtifacts.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../../plan-matrix/PlanMatrix.psm1') -Force

$repository = 'libtmux/libtmux-powershell'
$source = 'a' * 40
$runId = 123
$bareNames = @(
    'plan', 'build and pack PowerShell modules'
    foreach ($shell in '7.4.20', '7.6.6') { foreach ($tmux in '3.3a', '3.4', '3.5', '3.6', '3.7a', '3.7b', '3.7c', '3.8', 'master') { "PowerShell $shell / tmux $tmux" } }
    'PowerShell 7.4.20 / tmux 3.2a rejected', 'PowerShell 7.4.20 / tmux 3.3 rejected'
    'PowerShell 7.4.20 / tmux 3.0a daemon behind a 3.3a client', 'PowerShell 7.4.20 / tmux 3.1c daemon behind a 3.3a client'
    'powershell gate'
)
# The release workflow calls ci.yml from a job named ci, and GitHub lists the
# called jobs as "<calling job> / <called job>".
$names = @($bareNames | ForEach-Object { "ci / $_" })

function Copy-Deep($Value) { ConvertTo-Json -InputObject $Value -Depth 10 | ConvertFrom-Json -AsHashtable }

function Assert-That([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw $Message }
}

function New-Job([int] $Index, [string] $Name, [string] $Status = 'completed', $Conclusion = 'success') {
    @{ id = $Index + 1; run_id = $runId; run_attempt = 1; head_sha = $source; name = $Name; status = $Status; conclusion = $Conclusion }
}

# The called jobs, then the release job that is running this check.
function New-Jobs([string[]] $Names) {
    $rows = [Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $Names.Count; $index++) { $rows.Add((New-Job $index $Names[$index])) }
    $rows.Add((New-Job $rows.Count 'gallery' 'in_progress' $null))
    @{ total_count = $rows.Count; jobs = $rows }
}

function New-Fixture {
    $repo = @{ id = 456; full_name = $repository }
    @{
        Run       = @{
            id = $runId; repository = $repo; head_repository = $repo.Clone(); path = '.github/workflows/release.yml'
            event = 'workflow_dispatch'; head_branch = 'master'; head_sha = $source; status = 'in_progress'
            conclusion = $null; run_attempt = 1
        }
        Jobs      = New-Jobs $names
        Artifacts = @{
            total_count = 1
            artifacts   = @(@{
                    id = 789; name = 'port-package'; expired = $false; digest = 'sha256:' + ('b' * 64)
                    workflow_run = @{ id = $runId; head_sha = $source; head_branch = 'master'; repository_id = 456; head_repository_id = 456 }
                })
        }
    }
}

function Get-Receipt($Fixture) {
    New-ReleaseReceipt -Run $Fixture.Run -Jobs $Fixture.Jobs -Artifacts $Fixture.Artifacts -SourceCommit $source -RunId $runId
}

function Assert-Refused([string] $Pattern, $Fixture, [string] $Label) {
    try { $null = Get-Receipt $Fixture } catch [InvalidOperationException] {
        Assert-That ($_.Exception.Message -cmatch $Pattern) "$Label was refused for the wrong reason: $($_.Exception.Message)"
        return
    }
    throw "$Label was not refused."
}

# A trusted run keeps the artifact and the source identity.
$receipt = Get-Receipt (New-Fixture)
Assert-That ($receipt.sourceCommit -ceq $source -and $receipt.repository -ceq $repository -and $receipt.runId -eq $runId) `
    'The receipt lost the source identity.'
Assert-That ($receipt.artifactId -eq 789 -and $receipt.artifactDigest -ceq ('sha256:' + ('b' * 64))) `
    'The receipt lost the artifact identity.'
Assert-That ($receipt.workflowPath -ceq '.github/workflows/ci.yml') 'The receipt names the wrong workflow.'
Assert-That ($receipt.runUrl -ceq "https://github.com/$repository/actions/runs/$runId") 'The receipt names the wrong run.'
Assert-That (!@(Compare-Object @($receipt.jobs | ForEach-Object { $_.name }) $names -CaseSensitive).Count) `
    'The receipt lists the wrong jobs.'
Assert-That ('gallery' -cnotin @($receipt.jobs | ForEach-Object { $_.name })) 'The receipt names the release job.'

# A stale, forked, pull request, wrong-workflow or unfinished run is refused.
$runChanges = @(
    @{ head_sha = 'c' * 40 }, @{ event = 'pull_request' }, @{ event = 'push' }, @{ event = 'schedule' }, @{ head_branch = 'feature' }
    @{ repository = @{ id = 456; full_name = 'other/repository' } }
    @{ head_repository = @{ id = 999; full_name = 'fork/repository' } }
    @{ path = '.github/workflows/other.yml' }, @{ path = '.github/workflows/ci.yml' }
    @{ status = 'completed'; conclusion = 'success' }, @{ status = 'queued' }, @{ conclusion = 'failure' }, @{ id = 999 }
)
foreach ($change in $runChanges) {
    $fixture = New-Fixture
    foreach ($key in $change.Keys) { $fixture.Run[$key] = $change[$key] }
    Assert-Refused 'Release run' $fixture "A run changed by $(($change.Keys) -join ',')"
}

# A missing, failed, duplicate, foreign, other-attempt or truncated job list is refused.
foreach ($kind in 'missing', 'failed', 'duplicate', 'foreign', 'attempt', 'truncated') {
    $fixture = New-Fixture
    $rows = $fixture.Jobs.jobs
    switch ($kind) {
        'missing' { $rows.RemoveAt(1); $fixture.Jobs.total_count-- }
        'failed' { $rows[1].conclusion = 'failure' }
        'duplicate' { $rows[1].name = $names[0] }
        'foreign' { $rows[1].head_sha = 'c' * 40 }
        'attempt' { $rows[1].run_attempt = 2 }
        'truncated' { $fixture.Jobs.total_count++ }
    }
    Assert-Refused 'Linux jobs' $fixture "A job list that is $kind"
}

# An unrelated, expired, ambiguous or unverified artifact is refused.
foreach ($kind in 'missing', 'expired', 'duplicate', 'foreign', 'source', 'digest', 'truncated') {
    $fixture = New-Fixture
    $artifact = $fixture.Artifacts.artifacts[0]
    switch ($kind) {
        'missing' { $artifact.name = 'evidence-other' }
        'expired' { $artifact.expired = $true }
        'duplicate' { $fixture.Artifacts.artifacts = @($artifact, (Copy-Deep $artifact)); $fixture.Artifacts.total_count++ }
        'foreign' { $artifact.workflow_run.id = 999 }
        'source' { $artifact.workflow_run.head_sha = 'c' * 40 }
        'digest' { $artifact.digest = $null }
        'truncated' { $fixture.Artifacts.total_count++ }
    }
    Assert-Refused 'package artifact' $fixture "An artifact that is $kind"
}

# The required jobs are the whole table the plan derives.
$manifest = Read-MatrixManifest (Join-Path $PSScriptRoot '../../plan-matrix/matrix.json')
$required = @(Get-RequiredJobs)
Assert-That (!@(Compare-Object $required $names -CaseSensitive).Count) 'The required jobs differ from the full table.'
$fullNames = Get-FullJobNames $manifest
$derived = @($fullNames | ForEach-Object { "ci / $_" })
Assert-That (!@(Compare-Object $required $derived -CaseSensitive).Count) 'The required jobs differ from the plan.'

# A call that covered only the edges, or dropped the master cells, is refused.
$edges = Get-PlanJobNames (New-MatrixPlan -Manifest $manifest -EventName push)
Assert-That ($edges.Count -lt $bareNames.Count) 'The edges plan is as large as the full plan.'
$fixture = New-Fixture
$fixture.Jobs = New-Jobs @($edges | Sort-Object | ForEach-Object { "ci / $_" })
Assert-Refused 'only the full-scope CI' $fixture 'A call that only covered the edges'
$fixture = New-Fixture
$fixture.Jobs = New-Jobs @($names | Where-Object { !$_.EndsWith('tmux master') })
Assert-Refused 'Linux jobs' $fixture 'A full call with the master cells missing'
$fixture = New-Fixture
$fixture.Jobs = New-Jobs $bareNames
Assert-Refused 'Linux jobs' $fixture 'Jobs that are not named for the calling job'

# The one release job must sit beside the called jobs, still running.
$cases = [ordered]@{
    absent   = { param($rows) $rows.RemoveAt($rows.Count - 1) }
    twice    = { param($rows) $rows.Add((New-Job 99 'gallery' 'in_progress' $null)) }
    stranger = { param($rows) $rows.Add((New-Job 99 'publish elsewhere')) }
    finished = { param($rows) $rows[$rows.Count - 1].status = 'completed'; $rows[$rows.Count - 1].conclusion = 'success' }
    foreign  = { param($rows) $rows[$rows.Count - 1].head_sha = 'c' * 40 }
    attempt  = { param($rows) $rows[$rows.Count - 1].run_attempt = 2 }
}
foreach ($kind in $cases.Keys) {
    $fixture = New-Fixture
    & $cases[$kind] $fixture.Jobs.jobs
    $fixture.Jobs.total_count = $fixture.Jobs.jobs.Count
    Assert-Refused 'Linux jobs' $fixture "A release job that is $kind"
}

# A called job that has not finished is refused.
$fixture = New-Fixture
$fixture.Jobs.jobs[0].status = 'in_progress'
$fixture.Jobs.jobs[0].conclusion = $null
Assert-Refused 'Linux jobs' $fixture 'A called job that has not finished'
'PASS release artifact provenance accepts a trusted run and refuses each way to fail'
