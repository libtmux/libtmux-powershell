# Plans the Linux CI matrix from matrix.json and the event. PlanMatrix.ps1 is
# the command line; tests/PlanMatrix.Tests.ps1 holds the rules to account.
Set-StrictMode -Version Latest

$script:Scopes = @('edges', 'full', 'custom')
$script:TmateModes = @('off', 'before-tests', 'on-failure')
$script:Events = @('push', 'pull_request', 'workflow_dispatch')
# Every item of tmux-ref is checked against this before it reaches a shell or a git command.
$script:RefPattern = '^[A-Za-z0-9._/-]{1,64}\z'
$script:AbbreviatedSha = '^[0-9a-f]{7,39}\z'
# A mistyped list should fail rather than fan out into a huge matrix.
$script:MaxRefs = 8
# The plan, the package build and the gate, which every run has.
$script:FixedJobs = 3
# Jobs named in the workflow that no matrix produces.
$script:PlanJob = 'plan'
$script:PackageJob = 'build and pack PowerShell modules'
$script:GateJob = 'powershell gate'

function Stop-Plan([string] $Message) {
    throw [InvalidOperationException]::new($Message)
}

function Read-MatrixManifest {
    [CmdletBinding()]
    param([string] $Path = (Join-Path $PSScriptRoot 'matrix.json'))
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
}

function Split-List([string] $Value) {
    $items = [Collections.Generic.List[string]]::new()
    foreach ($each in $Value.Split(',')) {
        $item = $each.Trim()
        if ($item -and !$items.Contains($item)) { $items.Add($item) }
    }
    $items.ToArray()
}

function Resolve-PlanScope([string] $EventName, [string] $Scope) {
    if ($Scope) {
        if ($Scope -cnotin $script:Scopes) {
            Stop-Plan "scope must be one of $($script:Scopes -join ', '), not '$Scope'"
        }
        return $Scope
    }
    if ($EventName -cin $script:Events) { return 'edges' }
    Stop-Plan "no scope is defined for the '$EventName' event"
}

function Get-EdgeVersions([string[]] $Supported) {
    $edges = [Collections.Generic.List[string]]::new()
    if ($Supported.Count) {
        $edges.Add($Supported[0])
        if ($Supported[-1] -cne $Supported[0]) { $edges.Add($Supported[-1]) }
    }
    $edges.ToArray()
}

function Assert-ScopeInputs([string] $Scope, [string] $TmuxRef) {
    if ($TmuxRef -and $Scope -cne 'custom') { Stop-Plan 'tmux-ref is only used with scope custom' }
}

function Assert-PlanCells($Cells) {
    if (!@($Cells).Count) { Stop-Plan 'the plan has no test leg' }
}

function Select-PowerShellVersions($Manifest, [string] $Requested) {
    $available = [ordered]@{}
    foreach ($each in $Manifest.powershell) { $available[$each.version] = $each }
    $chosen = @(Split-List $Requested)
    foreach ($version in $chosen) {
        if (!$available.Contains($version)) {
            Stop-Plan "pwsh must name versions from $($available.Keys -join ', '), not '$version'"
        }
    }
    if ($chosen.Count) { foreach ($version in $chosen) { $available[$version] } } else { $Manifest.powershell }
}

function Test-PlanRef([string] $Item) {
    if ($Item -cnotmatch $script:RefPattern) {
        Stop-Plan "tmux-ref item '$Item' must match $($script:RefPattern -replace '\\z$', '$')"
    }
    if ($Item.StartsWith('-') -or $Item.Contains('..') -or $Item.EndsWith('.lock') -or $Item.EndsWith('/')) {
        Stop-Plan "tmux-ref item '$Item' is not a usable git ref"
    }
    if ($Item -cmatch $script:AbbreviatedSha) {
        Stop-Plan "tmux-ref item '$Item' looks like an abbreviated commit; give the full 40-hex SHA"
    }
    $Item
}

function Get-CustomRefs([string] $TmuxRef) {
    $items = @(Split-List $TmuxRef)
    if (!$items.Count) { Stop-Plan 'scope custom needs tmux-ref, a comma-separated list of tmux refs' }
    if ($items.Count -gt $script:MaxRefs) {
        Stop-Plan "tmux-ref names $($items.Count) refs; at most $($script:MaxRefs) fit one run"
    }
    foreach ($item in $items) { Test-PlanRef $item }
}

# A name in the table keeps its pinned commit and its build path. Any other ref
# is resolved to a commit and built from source when the job runs.
function Get-TmuxEntries($Manifest, [string] $Scope, [string] $TmuxRef) {
    $table = [ordered]@{}
    foreach ($each in @($Manifest.supported) + @($Manifest.development)) { $table[$each.tmux] = $each }
    $supported = [string[]] @($Manifest.supported | ForEach-Object { $_.tmux })
    if ($Scope -ceq 'full') { return @($table.Values) }
    if ($Scope -ceq 'edges') { return @(Get-EdgeVersions $supported | ForEach-Object { $table[$_] }) }
    @(Get-CustomRefs $TmuxRef | ForEach-Object {
        if ($table.Contains($_)) { $table[$_] } else { @{ tmux = $_; commit = ''; build = 'ref' } }
    })
}

function New-PlanCell($PowerShell, $Tmux) {
    [ordered]@{
        powershell = $PowerShell.version
        powershell_sha256 = $PowerShell.sha256
        tmux = $Tmux.tmux
        tmux_commit = $Tmux.commit
        build = $Tmux.build
        # Artifact names cannot hold a slash, which a branch name can.
        slug = $Tmux.tmux.Replace('/', '-')
        tmate = 'off'
    }
}

# The refusal lanes run on the first PowerShell version.
function Select-PlanLanes($Manifest, [string] $Scope) {
    if ($Scope -cne 'full') { return @{ reject = @(); old_daemon = @() } }
    $base = $Manifest.powershell[0]
    $client = $Manifest.supported[0]
    @{
        reject = @($Manifest.rejected | ForEach-Object {
            [ordered]@{ powershell = $base.version; powershell_sha256 = $base.sha256
                tmux = $_.tmux; tmux_commit = $_.commit }
        })
        old_daemon = @($Manifest.oldDaemon | ForEach-Object {
            [ordered]@{ powershell = $base.version; powershell_sha256 = $base.sha256
                tmux = $_.tmux; tmux_commit = $_.commit
                client_tmux = $client.tmux; client_commit = $client.commit }
        })
    }
}

# Gives exactly one leg the debug session, or fails.
function Set-PlanTmate([string] $EventName, [string] $Mode, $Cells, $Lanes) {
    if ($Mode -cnotin $script:TmateModes) {
        Stop-Plan "tmate must be one of $($script:TmateModes -join ', '), not '$Mode'"
    }
    if ($Mode -ceq 'off') { return }
    if ($EventName -cne 'workflow_dispatch') { Stop-Plan 'tmate is only available on a workflow_dispatch run' }
    $legs = @($Cells).Count + @($Lanes.reject).Count + @($Lanes.old_daemon).Count
    if ($legs -ne 1) {
        Stop-Plan "tmate needs exactly one leg and this run has $legs; use scope custom with one tmux-ref and one pwsh version"
    }
    @($Cells)[0].tmate = $Mode
}

function New-MatrixPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Manifest,
        [Parameter(Mandatory)] [string] $EventName,
        [string] $Scope = '',
        [string] $TmuxRef = '',
        [string] $Pwsh = '',
        [string] $Tmate = ''
    )
    $chosen = Resolve-PlanScope $EventName $Scope
    Assert-ScopeInputs $chosen $TmuxRef
    $cells = @(foreach ($tmux in @(Get-TmuxEntries $Manifest $chosen $TmuxRef)) {
        foreach ($shell in @(Select-PowerShellVersions $Manifest $Pwsh)) { New-PlanCell $shell $tmux }
    })
    Assert-PlanCells $cells
    $lanes = Select-PlanLanes $Manifest $chosen
    Set-PlanTmate $EventName $(if ($Tmate) { $Tmate } else { 'off' }) $cells $lanes
    [ordered]@{
        scope = $chosen
        matrix = [ordered]@{ include = $cells }
        reject = @($lanes.reject)
        old_daemon = @($lanes.old_daemon)
        expected_jobs = $script:FixedJobs + $cells.Count + @($lanes.reject).Count + @($lanes.old_daemon).Count
    }
}

# Names the jobs a plan produces, as the workflow names them.
function Get-PlanJobNames($Plan) {
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($name in @($script:PlanJob, $script:PackageJob, $script:GateJob)) { $null = $names.Add($name) }
    foreach ($each in $Plan.matrix.include) { $null = $names.Add("PowerShell $($each.powershell) / tmux $($each.tmux)") }
    foreach ($each in $Plan.reject) { $null = $names.Add("PowerShell $($each.powershell) / tmux $($each.tmux) rejected") }
    foreach ($each in $Plan.old_daemon) {
        $null = $names.Add("PowerShell $($each.powershell) / tmux $($each.tmux) daemon behind a $($each.client_tmux) client")
    }
    , $names
}

# Names every job of a full-scope run, which is what a release is bound to.
function Get-FullJobNames($Manifest) {
    Get-PlanJobNames (New-MatrixPlan -Manifest $Manifest -EventName workflow_dispatch -Scope full)
}

function Get-NeedResult($Needs, [string] $Job) {
    if ($Needs.ContainsKey($Job) -and $Needs[$Job] -is [System.Collections.IDictionary] -and $Needs[$Job].Contains('result')) {
        return [string] $Needs[$Job]['result']
    }
    ''
}

# The matrix and the package build must succeed. A refusal lane must succeed
# when the plan scheduled it and be skipped when the plan left it out, so a
# skipped lane that was planned cannot pass.
function Test-GateNeeds($Needs) {
    $problems = [Collections.Generic.List[string]]::new()
    foreach ($job in @($script:PlanJob, 'port', 'matrix')) {
        $result = Get-NeedResult $Needs $job
        if ($result -cne 'success') {
            $problems.Add("$job finished $(if ($result) { $result } else { 'missing' }), not success")
        }
    }
    $outputs = @{}
    if ($Needs.ContainsKey($script:PlanJob) -and $Needs[$script:PlanJob].Contains('outputs')) {
        $outputs = $Needs[$script:PlanJob]['outputs']
    }
    foreach ($pair in @(@('reject', 'run_reject'), @('reject-old-daemon', 'run_old_daemon'))) {
        $planned = $outputs.Contains($pair[1]) -and $outputs[$pair[1]] -ceq 'true'
        $wanted = if ($planned) { 'success' } else { 'skipped' }
        $result = Get-NeedResult $Needs $pair[0]
        if ($result -cne $wanted) {
            $problems.Add("$($pair[0]) finished $(if ($result) { $result } else { 'missing' }), not $wanted")
        }
    }
    $problems.ToArray()
}

function Get-PlanSummary($Plan) {
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add("### tmux plan: $($Plan.scope)")
    $lines.Add('')
    $lines.Add("Expected jobs in this workflow: $($Plan.expected_jobs)")
    $lines.Add('')
    foreach ($each in $Plan.matrix.include) { $lines.Add("- PowerShell $($each.powershell) with tmux $($each.tmux) ($($each.build))") }
    foreach ($each in $Plan.reject) { $lines.Add("- tmux $($each.tmux) is refused") }
    foreach ($each in $Plan.old_daemon) { $lines.Add("- tmux $($each.tmux) daemon is refused") }
    ($lines -join "`n") + "`n"
}

# Flattens a plan into single-line workflow outputs.
function Get-PlanOutputs($Plan) {
    [ordered]@{
        scope = $Plan.scope
        matrix = ConvertTo-Json -InputObject $Plan.matrix -Compress -Depth 6
        reject = ConvertTo-Json -InputObject ([ordered]@{ include = @($Plan.reject) }) -Compress -Depth 6
        run_reject = if (@($Plan.reject).Count) { 'true' } else { 'false' }
        old_daemon = ConvertTo-Json -InputObject ([ordered]@{ include = @($Plan.old_daemon) }) -Compress -Depth 6
        run_old_daemon = if (@($Plan.old_daemon).Count) { 'true' } else { 'false' }
        expected_jobs = [string] $Plan.expected_jobs
    }
}

Export-ModuleMember -Function Read-MatrixManifest, New-MatrixPlan, Get-PlanJobNames, Get-FullJobNames,
    Test-GateNeeds, Get-PlanSummary, Get-PlanOutputs, Split-List
