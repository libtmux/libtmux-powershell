# Binds a release to the tested archives of the CI run it calls. ReleaseArtifacts.ps1
# is the command line; tests/ReleaseArtifacts.Tests.ps1 holds the rules to account.
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../plan-matrix/PlanMatrix.psm1') -Force

$script:Repository = 'libtmux/libtmux-powershell'
# The release workflow calls the CI workflow at scope full, so the run to bind
# is the release run itself, still in progress, and the CI jobs appear in it
# under the name of the job that calls them.
$script:Workflow = '.github/workflows/ci.yml'
$script:ReleaseWorkflow = '.github/workflows/release.yml'
$script:CallerJob = 'ci'
$script:ReleaseJob = 'gallery'

# At scope full the CI runs the whole table, tmux master and the refusal lanes,
# which the plan derives from the manifest. A call with any fewer jobs is not
# the proof a release needs.
function Get-RequiredJobs([string] $Manifest = (Join-Path $PSScriptRoot '../plan-matrix/matrix.json')) {
    $names = Get-FullJobNames (Read-MatrixManifest $Manifest)
    @($names | ForEach-Object { "$($script:CallerJob) / $_" })
}

# The job of the release workflow that calls the CI workflow.
function Get-CallerJobName { $script:CallerJob }

function Test-PositiveInteger($Value) {
    ($Value -is [int] -or $Value -is [long]) -and $Value -gt 0
}

function Get-Field($Table, [string] $Key) {
    if ($Table -is [System.Collections.IDictionary] -and $Table.Contains($Key)) { return $Table[$Key] }
    $null
}

function Get-Table($Table, [string] $Key) {
    $value = Get-Field $Table $Key
    if ($value -is [System.Collections.IDictionary]) { $value } else { @{} }
}

function Stop-Release([string] $Message) {
    throw [InvalidOperationException]::new($Message)
}

function Test-ReleaseRun($Run, [string] $SourceCommit, $RunId) {
    $repository = Get-Table $Run 'repository'
    $head = Get-Table $Run 'head_repository'
    $attempt = Get-Field $Run 'run_attempt'
    $valid = ($SourceCommit -cmatch '^[0-9a-f]{40}$') -and (Test-PositiveInteger $RunId) -and
        (Get-Field $Run 'id') -eq $RunId -and
        (Get-Field $repository 'full_name') -ceq $script:Repository -and
        (Get-Field $head 'full_name') -ceq $script:Repository -and
        (Test-PositiveInteger (Get-Field $repository 'id')) -and
        (Get-Field $repository 'id') -eq (Get-Field $head 'id') -and
        (Get-Field $Run 'path') -ceq $script:ReleaseWorkflow -and
        (Get-Field $Run 'event') -ceq 'workflow_dispatch' -and
        (Get-Field $Run 'head_branch') -ceq 'master' -and
        (Get-Field $Run 'head_sha') -ceq $SourceCommit -and
        (Get-Field $Run 'status') -ceq 'in_progress' -and
        $null -eq (Get-Field $Run 'conclusion') -and
        (Test-PositiveInteger $attempt)
    if (!$valid) {
        Stop-Release ('Release run must be this same-repository master workflow_dispatch run ' +
            'of the release workflow, at the release commit')
    }
}

function Test-ReleaseJobs($Jobs, $Run, [string] $SourceCommit, $RunId, [string[]] $Required) {
    $rows = @(Get-Field $Jobs 'jobs')
    $own = @($rows | Where-Object { (Get-Field $_ 'name') -ceq $script:ReleaseJob })
    $called = @($rows | Where-Object { (Get-Field $_ 'name') -cne $script:ReleaseJob })
    $attempt = Get-Field $Run 'run_attempt'
    $calledNames = @($called | ForEach-Object { Get-Field $_ 'name' })
    $valid = (Get-Field $Jobs 'total_count') -eq $rows.Count -and $own.Count -eq 1 -and
        (Test-PositiveInteger (Get-Field $own[0] 'id')) -and
        (Get-Field $own[0] 'run_id') -eq $RunId -and
        (Get-Field $own[0] 'run_attempt') -eq $attempt -and
        (Get-Field $own[0] 'head_sha') -ceq $SourceCommit -and
        (Get-Field $own[0] 'status') -ceq 'in_progress' -and
        $called.Count -eq $Required.Count -and
        !@($calledNames | Where-Object { $_ -cnotin $Required }).Count -and
        !@($Required | Where-Object { $_ -cnotin $calledNames }).Count -and
        !@($called | Where-Object {
            !(Test-PositiveInteger (Get-Field $_ 'id')) -or (Get-Field $_ 'run_id') -ne $RunId -or
            (Get-Field $_ 'run_attempt') -ne $attempt -or (Get-Field $_ 'head_sha') -cne $SourceCommit -or
            (Get-Field $_ 'status') -cne 'completed' -or (Get-Field $_ 'conclusion') -cne 'success'
        }).Count
    if (!$valid) {
        Stop-Release ('Linux jobs must include the successful build, the supported cells, tmux master, ' +
            'the rejection cells and gate of the full-scope CI this run called, ' +
            'from this attempt, beside the one release job; only the full-scope CI ' +
            'runs them all')
    }
    $called
}

function Get-PackageArtifact($Artifacts, $Run, [string] $SourceCommit, $RunId) {
    $all = @(Get-Field $Artifacts 'artifacts')
    $named = @($all | Where-Object { (Get-Field $_ 'name') -ceq 'port-package' })
    if ((Get-Field $Artifacts 'total_count') -ne $all.Count -or $named.Count -ne 1) {
        Stop-Release 'CI package artifact must be uniquely identified in the complete artifact list'
    }
    $artifact = $named[0]
    $origin = Get-Table $artifact 'workflow_run'
    $repositoryId = (Get-Table $Run 'repository')['id']
    $digest = Get-Field $artifact 'digest'
    $valid = (Test-PositiveInteger (Get-Field $artifact 'id')) -and
        (Get-Field $artifact 'expired') -eq $false -and
        ($digest -is [string] -and $digest -cmatch '^sha256:[0-9a-f]{64}$') -and
        (Get-Field $origin 'id') -eq $RunId -and
        (Get-Field $origin 'head_sha') -ceq $SourceCommit -and
        (Get-Field $origin 'head_branch') -ceq 'master' -and
        (Get-Field $origin 'repository_id') -eq $repositoryId -and
        (Get-Field $origin 'head_repository_id') -eq $repositoryId
    if (!$valid) { Stop-Release 'CI package artifact must be unexpired and belong to the verified source and run' }
    $artifact
}

# Returns the receipt for a run, its jobs and its artifacts, or throws why not.
function New-ReleaseReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Run,
        [Parameter(Mandatory)] $Jobs,
        [Parameter(Mandatory)] $Artifacts,
        [Parameter(Mandatory)] [string] $SourceCommit,
        [Parameter(Mandatory)] $RunId,
        [string[]] $RequiredJobs = (Get-RequiredJobs)
    )
    Test-ReleaseRun $Run $SourceCommit $RunId
    $called = @(Test-ReleaseJobs $Jobs $Run $SourceCommit $RunId $RequiredJobs)
    $artifact = Get-PackageArtifact $Artifacts $Run $SourceCommit $RunId
    [ordered]@{
        schemaVersion = 1
        repository = $script:Repository
        sourceCommit = $SourceCommit
        workflowPath = $script:Workflow
        runId = $RunId
        runAttempt = $Run['run_attempt']
        runUrl = "https://github.com/$($script:Repository)/actions/runs/$RunId"
        artifactId = $artifact['id']
        artifactName = $artifact['name']
        artifactDigest = $artifact['digest']
        jobs = @($called | ForEach-Object { [ordered]@{ id = $_['id']; name = $_['name'] } })
    }
}

function Read-GitHubApi([string] $Path) {
    if (!$env:GH_TOKEN) { throw [InvalidOperationException]::new('GH_TOKEN is required to inspect the trusted CI artifacts') }
    $headers = @{
        Accept = 'application/vnd.github+json'
        Authorization = "Bearer $($env:GH_TOKEN)"
        'X-GitHub-Api-Version' = '2022-11-28'
    }
    $response = Invoke-WebRequest -Uri "https://api.github.com/repos/$($script:Repository)/$Path" `
        -Headers $headers -TimeoutSec 30
    $response.Content | ConvertFrom-Json -AsHashtable
}

Export-ModuleMember -Function Get-CallerJobName, Get-RequiredJobs, New-ReleaseReceipt, Read-GitHubApi
