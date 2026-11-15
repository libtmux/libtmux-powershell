# Proves the matrix plan picks what each event should run, and that it can fail.
#
# Every rule has a check, and every check has a deliberate break: the rule is
# replaced with its absence and the check has to notice. A check that passes
# with its rule removed would prove nothing about the rule.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$module = Import-Module (Join-Path $PSScriptRoot '../PlanMatrix.psm1') -Force -PassThru
$manifest = Read-MatrixManifest (Join-Path $PSScriptRoot '../matrix.json')
$supported = @($manifest.supported | ForEach-Object { $_.tmux })
$development = @($manifest.development | ForEach-Object { $_.tmux })
$shells = @($manifest.powershell | ForEach-Object { $_.version })
$oldest, $newest = $supported[0], $supported[-1]

function Assert-Same($Expected, $Actual, [string] $Message) {
    $want = ConvertTo-Json -InputObject $Expected -Compress -Depth 8
    $got = ConvertTo-Json -InputObject $Actual -Compress -Depth 8
    if ($want -cne $got) { throw "$Message`n  expected $want`n  observed $got" }
}

function Assert-That([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw $Message }
}

function Get-Plan([string] $EventName, [hashtable] $With = @{}) {
    New-MatrixPlan -Manifest $manifest -EventName $EventName @With
}

function Get-Tmux($Plan) { @($Plan.matrix.include | ForEach-Object { $_.tmux } | Select-Object -Unique) }

function Assert-Refused([string] $Pattern, [string] $EventName = 'workflow_dispatch', [hashtable] $With = @{}) {
    try { $null = Get-Plan $EventName $With } catch [InvalidOperationException] {
        Assert-That ($_.Exception.Message -cmatch $Pattern) "The plan was refused for the wrong reason: $($_.Exception.Message)"
        return
    }
    throw "The plan was not refused: $Pattern"
}

function Get-Needs([string] $Plan = 'success', [string] $Port = 'success', [string] $Matrix = 'success',
    [string] $Reject = 'skipped', [string] $Old = 'skipped', [bool] $Planned = $false) {
    $listed = if ($Planned) { 'true' } else { 'false' }
    @{
        plan = @{ result = $Plan; outputs = @{ run_reject = $listed; run_old_daemon = $listed } }
        port = @{ result = $Port }
        matrix = @{ result = $Matrix }
        reject = @{ result = $Reject }
        'reject-old-daemon' = @{ result = $Old }
    }
}

$checks = [ordered]@{}

$checks.PushRunsTheEdgesOnly = {
    $plan = Get-Plan push
    Assert-Same 'edges' $plan.scope 'A push is not planned at the edges.'
    Assert-Same @($oldest, $newest) @(Get-Tmux $plan) 'A push does not run the oldest and newest tmux.'
    $legs = @($plan.matrix.include | ForEach-Object { "$($_.tmux) $($_.powershell)" })
    Assert-Same @(foreach ($tmux in $oldest, $newest) { foreach ($shell in $shells) { "$tmux $shell" } }) $legs `
        'The edges do not cover every PowerShell version.'
    Assert-That (!@($plan.reject).Count -and !@($plan.old_daemon).Count) 'A push runs the refusal lanes.'
    Assert-That ('master' -cnotin (Get-Tmux $plan)) 'A push runs tmux master.'
}
$checks.PullRequestRunsTheEdgesOnly = {
    $plan = Get-Plan pull_request
    Assert-Same 'edges' $plan.scope 'A pull request is not planned at the edges.'
    Assert-Same @($oldest, $newest) @(Get-Tmux $plan) 'A pull request does not run the edges.'
    Assert-That (!@($plan.reject).Count -and !@($plan.old_daemon).Count) 'A pull request runs the refusal lanes.'
}
$checks.DispatchDefaultsToTheEdges = {
    Assert-Same @($oldest, $newest) @(Get-Tmux (Get-Plan workflow_dispatch)) 'A dispatch does not default to the edges.'
}
$checks.FullRunsTheWholeTable = {
    $plan = Get-Plan workflow_dispatch @{ Scope = 'full' }
    Assert-Same 'full' $plan.scope 'The full scope was not kept.'
    Assert-Same @($supported + $development) @(Get-Tmux $plan) 'The full scope omits part of the table.'
    Assert-Same (($supported.Count + $development.Count) * $shells.Count) $plan.matrix.include.Count 'The full scope omits a leg.'
    Assert-Same @($manifest.rejected | ForEach-Object { $_.tmux }) @($plan.reject | ForEach-Object { $_.tmux }) 'The full scope omits a rejected release.'
    Assert-Same @($manifest.oldDaemon | ForEach-Object { $_.tmux }) @($plan.old_daemon | ForEach-Object { $_.tmux }) 'The full scope omits an old daemon.'
    Assert-Same @($oldest) @($plan.old_daemon | ForEach-Object { $_.client_tmux } | Select-Object -Unique) 'The old daemons have the wrong client.'
    Assert-Same @($shells[0]) @($plan.reject | ForEach-Object { $_.powershell } | Select-Object -Unique) 'The refusal lanes use the wrong PowerShell.'
}
$checks.ATableNameKeepsItsPinAndOtherRefsAreBuilt = {
    $sha = 'a' * 40
    $plan = Get-Plan workflow_dispatch @{ Scope = 'custom'; TmuxRef = "$($supported[1]), $newest,master,3.6b,$sha"; Pwsh = $shells[0] }
    $byName = [ordered]@{}
    foreach ($each in $plan.matrix.include) { $byName[$each.tmux] = $each }
    Assert-Same @($supported[1], $newest, 'master', '3.6b', $sha) @($byName.Keys) 'The custom refs were reordered or lost.'
    $pinned = $manifest.supported[1]
    Assert-Same @($pinned.build, $pinned.commit) @($byName[$supported[1]].build, $byName[$supported[1]].tmux_commit) 'A table name lost its pin.'
    Assert-Same $manifest.supported[-1].build $byName[$newest].build 'A table name lost its build path.'
    Assert-Same 'clone' $byName['master'].build 'Master is not cloned.'
    Assert-Same @('ref', '') @($byName['3.6b'].build, $byName['3.6b'].tmux_commit) 'An outside tag is not built from a ref.'
    Assert-Same 'ref' $byName[$sha].build 'An outside commit is not built from a ref.'
    $slashed = Get-Plan workflow_dispatch @{ Scope = 'custom'; TmuxRef = 'feature/x' }
    Assert-Same @('feature-x') @($slashed.matrix.include | ForEach-Object { $_.slug } | Select-Object -Unique) 'A slash survived into an artifact name.'
}
$checks.ACustomRunNeedsRefs = { Assert-Refused 'needs tmux-ref' -With @{ Scope = 'custom' } }
$checks.ARefListNeedsTheCustomScope = {
    Assert-Refused 'only used with scope custom' -With @{ TmuxRef = '3.6b' }
    Assert-Refused 'only used with scope custom' -With @{ Scope = 'full'; TmuxRef = '3.6b' }
}
$checks.AScopeMustBeKnown = { Assert-Refused 'scope must be one of' -With @{ Scope = 'everything' } }
$checks.AnUnknownEventIsRefused = { Assert-Refused 'no scope is defined' -EventName schedule }
$checks.EveryRefIsValidated = {
    $bad = @('3.6b;rm', '$(id)', 'a b', 'x`id`', ('a' * 65), '--upload-pack=x', '-x', 'a..b', 'topic.lock', 'topic/', 'deadbeef', 'é')
    foreach ($item in $bad) {
        $refused = $false
        try { $null = Get-Plan workflow_dispatch @{ Scope = 'custom'; TmuxRef = "$newest,$item" } } catch [InvalidOperationException] { $refused = $true }
        Assert-That $refused "A bad ref was planned: $item"
    }
    foreach ($good in @('next-3.8', 'feature/x_y.z', ('a' * 40), 'A-b_c.1')) {
        Assert-Same @($good) @(Get-Tmux (Get-Plan workflow_dispatch @{ Scope = 'custom'; TmuxRef = $good })) "A good ref was refused: $good"
    }
}
$checks.TooManyRefsAreRefused = {
    $eight = (0..7 | ForEach-Object { "v$_" }) -join ','
    Assert-Same 8 @(Get-Tmux (Get-Plan workflow_dispatch @{ Scope = 'custom'; TmuxRef = $eight })).Count 'Eight refs were refused.'
    Assert-Refused 'fit one run' -With @{ Scope = 'custom'; TmuxRef = "$eight,v8" }
}
$checks.APwshInputNarrowsTheStack = {
    $plan = Get-Plan workflow_dispatch @{ Pwsh = $shells[1] }
    Assert-Same @($shells[1]) @($plan.matrix.include | ForEach-Object { $_.powershell } | Select-Object -Unique) 'The pwsh input did not narrow the shells.'
    Assert-Same @($manifest.powershell[1].sha256) @($plan.matrix.include | ForEach-Object { $_.powershell_sha256 } | Select-Object -Unique) 'The narrowed shell has the wrong digest.'
    Assert-Same @($oldest, $newest) @(Get-Tmux $plan) 'Narrowing the shell changed the tmux versions.'
}
$checks.AnUnknownPwshIsRefused = { Assert-Refused 'pwsh must name versions' -With @{ Pwsh = '7.2.0' } }
$checks.OneLegGetsTheDebugSession = {
    $plan = Get-Plan workflow_dispatch @{ Scope = 'custom'; TmuxRef = 'master'; Pwsh = $shells[0]; Tmate = 'on-failure' }
    Assert-Same @('on-failure') @($plan.matrix.include | ForEach-Object { $_.tmate }) 'The one leg got no debug session.'
}
$checks.NoDebugSessionByDefault = {
    $plan = Get-Plan workflow_dispatch @{ Scope = 'custom'; TmuxRef = 'master'; Pwsh = $shells[0] }
    Assert-Same @('off') @($plan.matrix.include | ForEach-Object { $_.tmate }) 'A leg got a debug session unasked.'
}
$checks.SeveralLegsCannotShareADebugSession = {
    Assert-Refused 'exactly one leg' -With @{ Tmate = 'before-tests' }
    Assert-Refused 'exactly one leg' -With @{ Scope = 'full'; Tmate = 'before-tests' }
    Assert-Refused 'exactly one leg' -With @{ Scope = 'custom'; TmuxRef = 'master'; Tmate = 'before-tests' }
    Assert-Refused 'exactly one leg' -With @{ Scope = 'custom'; TmuxRef = "$oldest,master"; Pwsh = $shells[0]; Tmate = 'before-tests' }
}
$checks.ADebugSessionNeedsADispatch = {
    Assert-Refused 'only available on a workflow_dispatch' -EventName push `
        -With @{ Scope = 'custom'; TmuxRef = 'master'; Pwsh = $shells[0]; Tmate = 'on-failure' }
}
$checks.ADebugModeMustBeKnown = {
    Assert-Refused 'tmate must be one of' -With @{ Scope = 'custom'; TmuxRef = 'master'; Pwsh = $shells[0]; Tmate = 'always' }
}
$checks.TheJobCountAddsUp = {
    Assert-Same (3 + 2 * $shells.Count) (Get-Plan push).expected_jobs 'A push counts the wrong jobs.'
    $full = Get-Plan workflow_dispatch @{ Scope = 'full' }
    Assert-Same (3 + ($supported.Count + $development.Count) * $shells.Count + $manifest.rejected.Count + $manifest.oldDaemon.Count) `
        $full.expected_jobs 'A full run counts the wrong jobs.'
}
$checks.TheManifestAloneDecidesTheTable = {
    $other = @{
        powershell = @(@{ version = '9.0.1'; sha256 = '1' * 64 })
        supported = @(@{ tmux = '9.1'; commit = 'a' * 40; build = 'core' }, @{ tmux = '9.2'; commit = 'b' * 40; build = 'core' },
            @{ tmux = '9.3'; commit = 'c' * 40; build = 'clone' })
        development = @(@{ tmux = 'next'; commit = ''; build = 'clone' })
        rejected = @(@{ tmux = '9.0'; commit = 'd' * 40 })
        oldDaemon = @(@{ tmux = '8.9'; commit = 'e' * 40 })
    }
    $edges = New-MatrixPlan -Manifest $other -EventName push
    Assert-Same @('9.1 9.0.1', '9.3 9.0.1') @($edges.matrix.include | ForEach-Object { "$($_.tmux) $($_.powershell)" }) 'The edges follow the workflow, not the manifest.'
    $full = New-MatrixPlan -Manifest $other -EventName workflow_dispatch -Scope full
    Assert-Same @('9.1', '9.2', '9.3', 'next') @(Get-Tmux $full) 'The full table follows the workflow, not the manifest.'
    Assert-Same @('9.0') @($full.reject | ForEach-Object { $_.tmux }) 'The refusal lane follows the workflow.'
    Assert-Same @('9.1', ('a' * 40)) @($full.old_daemon[0].client_tmux, $full.old_daemon[0].client_commit) 'The old-daemon client follows the workflow.'
    $custom = New-MatrixPlan -Manifest $other -EventName workflow_dispatch -Scope custom -TmuxRef 9.2
    Assert-Same ('b' * 40) $custom.matrix.include[0].tmux_commit 'A custom table name lost its pin.'
}
$checks.TheMatrixIsNeverEmpty = {
    $empty = $manifest.Clone()
    $empty.supported = @()
    $empty.development = @()
    $refused = $false
    try { $null = New-MatrixPlan -Manifest $empty -EventName push } catch [InvalidOperationException] {
        $refused = $_.Exception.Message -cmatch 'no test leg'
    }
    Assert-That $refused 'An empty matrix was planned.'
}
$checks.ASingleReleaseIsOneEdge = {
    $only = $manifest.Clone()
    $only.supported = @($manifest.supported[-1])
    Assert-Same @($newest) @(Get-Tmux (New-MatrixPlan -Manifest $only -EventName push)) 'A single release is not one edge.'
}
$checks.JobNamesFollowThePlan = {
    $full = Get-Plan workflow_dispatch @{ Scope = 'full' }
    $names = Get-FullJobNames $manifest
    Assert-Same $full.expected_jobs $names.Count 'The job names miss a job of the full plan.'
    Assert-That $names.Contains("PowerShell $($shells[1]) / tmux master") 'No job name for tmux master.'
    Assert-That $names.Contains("PowerShell $($shells[0]) / tmux $($manifest.rejected[0].tmux) rejected") 'No job name for a rejected release.'
    Assert-That $names.Contains("PowerShell $($shells[0]) / tmux $($manifest.oldDaemon[0].tmux) daemon behind a $oldest client") 'No job name for an old daemon.'
    foreach ($fixed in 'plan', 'build and pack PowerShell modules', 'powershell gate') {
        Assert-That $names.Contains($fixed) "No job name for $fixed."
    }
    Assert-That (!(Get-PlanJobNames (Get-Plan push)).Contains("PowerShell $($shells[0]) / tmux master")) 'An edges run names tmux master.'
}
$checks.TheGatePassesWhatThePlanScheduled = {
    Assert-Same 0 @(Test-GateNeeds (Get-Needs)).Count 'The gate refused a run with no lanes.'
    Assert-Same 0 @(Test-GateNeeds (Get-Needs -Reject success -Old success -Planned $true)).Count 'The gate refused the lanes it scheduled.'
}
$checks.TheGateNeedsThePlanThePackageAndTheMatrix = {
    foreach ($broken in @((Get-Needs -Plan failure), (Get-Needs -Port failure), (Get-Needs -Port skipped),
            (Get-Needs -Matrix failure), (Get-Needs -Matrix cancelled))) {
        Assert-That (@(Test-GateNeeds $broken).Count -gt 0) 'The gate passed a failed or skipped required job.'
    }
    $missing = Get-Needs
    $missing.Remove('matrix')
    Assert-That (@(Test-GateNeeds $missing).Count -gt 0) 'The gate passed a missing matrix job.'
}
$checks.APlannedLaneThatWasSkippedFailsTheGate = {
    foreach ($needs in @((Get-Needs -Reject skipped -Old success -Planned $true), (Get-Needs -Reject success -Old skipped -Planned $true),
            (Get-Needs -Reject failure -Old success -Planned $true))) {
        Assert-That (@(Test-GateNeeds $needs).Count -gt 0) 'The gate passed a planned lane that did not succeed.'
    }
}
$checks.ALaneThePlanLeftOutMustNotHaveRun = {
    Assert-That (@(Test-GateNeeds (Get-Needs -Reject success)).Count -gt 0) 'The gate passed a lane the plan left out.'
    Assert-That (@(Test-GateNeeds (Get-Needs -Old failure)).Count -gt 0) 'The gate passed a failed unplanned lane.'
}

# A deliberate break swaps one rule of the module for its absence, or changes one
# constant, and names the check that has to notice. A function body is a script
# block, a constant is a value.
function Get-Original([string] $Name) { & $module { param($n) (Get-Item "function:$n").ScriptBlock } $Name }
$original = @{}
foreach ($name in 'Select-PlanLanes', 'Test-GateNeeds') { $original[$name] = Get-Original $name }

function Get-GateWithout([string] $Pattern) {
    { param($Needs) @(& $original['Test-GateNeeds'] $Needs | Where-Object { $_ -notmatch $Pattern }) }.GetNewClosure()
}

$breaks = @(
    @('the edges rule takes every version', 'Get-EdgeVersions', { param([string[]] $Supported) $Supported }, 'PushRunsTheEdgesOnly'),
    @('the edges are written into the plan', 'Get-EdgeVersions', { param([string[]] $Supported) '3.3a', '3.8' }, 'TheManifestAloneDecidesTheTable'),
    @('a dispatch ignores the scope it was given', 'Resolve-PlanScope', { param([string] $EventName, [string] $Scope) 'edges' }, 'FullRunsTheWholeTable'),
    @('an unknown scope is accepted', 'Resolve-PlanScope', { param([string] $EventName, [string] $Scope) if ($Scope) { $Scope } else { 'edges' } }, 'AScopeMustBeKnown'),
    @('the edges run the refusal lanes', 'Select-PlanLanes', { param($Manifest, [string] $Scope) & $original['Select-PlanLanes'] $Manifest 'full' }, 'PushRunsTheEdgesOnly'),
    @('the full scope drops its lanes', 'Select-PlanLanes', { param($Manifest, [string] $Scope) & $original['Select-PlanLanes'] $Manifest 'edges' }, 'FullRunsTheWholeTable'),
    @('refs the scope ignores are accepted', 'Assert-ScopeInputs', { param([string] $Scope, [string] $TmuxRef) }, 'ARefListNeedsTheCustomScope'),
    @('a ref is not validated', 'Test-PlanRef', { param([string] $Item) $Item }, 'EveryRefIsValidated'),
    @('the ref count is unlimited', '$MaxRefs', 1000, 'TooManyRefsAreRefused'),
    @('the pwsh input is ignored', 'Select-PowerShellVersions', { param($Manifest, [string] $Requested) $Manifest.powershell }, 'APwshInputNarrowsTheStack'),
    @('an unknown pwsh is accepted', 'Select-PowerShellVersions', {
            param($Manifest, [string] $Requested)
            $chosen = @($Manifest.powershell | Where-Object { $_.version -in ($Requested -split ',') })
            if ($chosen.Count) { $chosen } else { $Manifest.powershell }
        }, 'AnUnknownPwshIsRefused'),
    @('no leg gets the debug session', 'Set-PlanTmate', { param([string] $EventName, [string] $Mode, $Cells, $Lanes) }, 'OneLegGetsTheDebugSession'),
    @('every leg gets the debug session', 'Set-PlanTmate', { param([string] $EventName, [string] $Mode, $Cells, $Lanes) foreach ($each in @($Cells)) { $each.tmate = $Mode } }, 'SeveralLegsCannotShareADebugSession'),
    @('an unknown debug mode is accepted', 'Set-PlanTmate', { param([string] $EventName, [string] $Mode, $Cells, $Lanes) }, 'ADebugModeMustBeKnown'),
    @('the job count omits the fixed jobs', '$FixedJobs', 0, 'TheJobCountAddsUp'),
    @('an empty matrix is emitted', 'Assert-PlanCells', { param($Cells) }, 'TheMatrixIsNeverEmpty'),
    @('the job names omit the matrix', 'Get-PlanJobNames', { param($Plan) , [Collections.Generic.HashSet[string]]::new([string[]] @('plan')) }, 'JobNamesFollowThePlan'),
    @('the gate ignores the refusal lanes', 'shadow:Test-GateNeeds', (Get-GateWithout '^reject'), 'APlannedLaneThatWasSkippedFailsTheGate'),
    @('the gate lets an unplanned lane run', 'shadow:Test-GateNeeds', (Get-GateWithout 'not skipped'), 'ALaneThePlanLeftOutMustNotHaveRun'),
    @('the gate expects every lane skipped', 'shadow:Test-GateNeeds', { param($Needs) $Needs.plan.outputs = @{ run_reject = 'false'; run_old_daemon = 'false' }; & $original['Test-GateNeeds'] $Needs }, 'TheGatePassesWhatThePlanScheduled'),
    @('the gate ignores the matrix', 'shadow:Test-GateNeeds', (Get-GateWithout '^matrix'), 'TheGateNeedsThePlanThePackageAndTheMatrix'),
    @('the gate ignores the package build', 'shadow:Test-GateNeeds', (Get-GateWithout '^port'), 'TheGateNeedsThePlanThePackageAndTheMatrix'),
    @('the gate ignores the plan', 'shadow:Test-GateNeeds', (Get-GateWithout '^plan'), 'TheGateNeedsThePlanThePackageAndTheMatrix')
)

# Run every check against the real module.
foreach ($name in $checks.Keys) {
    try { & $checks[$name] } catch { throw "Check $name failed on the real module: $($_.Exception.Message)" }
}

# Replace each rule in turn and require its check to fail.
$escaped = [Collections.Generic.List[string]]::new()
foreach ($break in $breaks) {
    $label, $target, $replacement, $check = $break
    $noticed = $false
    try {
        if ($target.StartsWith('shadow:')) {
            Set-Item -Path "function:$($target.Substring(7))" -Value $replacement
        } elseif ($target.StartsWith('$')) {
            & $module { param($n, $v) Set-Variable -Name $n -Value $v -Scope Script } $target.Substring(1) $replacement
        } else {
            & $module { param($n, $b) Set-Item -Path "function:script:$n" -Value $b } $target $replacement
        }
        try { & $checks[$check] } catch { $noticed = $true }
    } finally {
        if ($target.StartsWith('shadow:')) { Remove-Item -Path "function:$($target.Substring(7))" }
        $module = Import-Module (Join-Path $PSScriptRoot '../PlanMatrix.psm1') -Force -PassThru
    }
    if (!$noticed) { $escaped.Add("$label (check $check)") }
}
if ($escaped.Count) { throw "These deliberate breaks went unnoticed: $($escaped -join '; ')" }
"PASS plan matrix: $($checks.Count) checks, $($breaks.Count) deliberate breaks noticed"
