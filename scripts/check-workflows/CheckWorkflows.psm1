# Checks that ci.yml takes its jobs from the plan and stays bound to the release
# gate, that release.yml proves the full set itself, and that no workflow calls
# apt-get or Python directly or pins a shared action to a moving ref. The
# workflows are read as text, because the CI step that runs this has no YAML
# parser. CheckWorkflows.ps1 is the command line; tests/CheckWorkflows.Tests.ps1
# plants each fault and expects it reported.
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../plan-matrix/PlanMatrix.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../release-artifacts/ReleaseArtifacts.psm1') -Force

$script:Tmate = 'mxschmitt/action-tmate'

# Maps each job id to its text.
function Get-WorkflowJobs([string] $Text) {
    $index = $Text.IndexOf("`njobs:`n", [StringComparison]::Ordinal)
    $body = if ($index -ge 0) { $Text.Substring($index + 7) } else { '' }
    $found = [ordered]@{}
    $name = $null
    foreach ($line in $body -split "`n") {
        $header = [regex]::Match($line, '^  ([A-Za-z0-9_-]+):\s*$')
        if ($header.Success) {
            $name = $header.Groups[1].Value
            $found[$name] = [Collections.Generic.List[string]]::new()
        } elseif ($name -and $line.StartsWith('    ')) {
            $found[$name].Add($line)
        } elseif ($line -and !$line.StartsWith(' ')) {
            $name = $null
        }
    }
    $jobs = [ordered]@{}
    foreach ($key in $found.Keys) { $jobs[$key] = $found[$key] -join "`n" }
    $jobs
}

function Get-JobField([string] $Job, [string] $Key) {
    $match = [regex]::Match($Job, "(?m)^    $([regex]::Escape($Key)): (.*)$")
    if ($match.Success) { $match.Groups[1].Value.Trim() } else { $null }
}

function Get-StepField([string] $Step, [string] $Key) {
    $match = [regex]::Match($Step, "(?m)^        $([regex]::Escape($Key)): (.*)$")
    if ($match.Success) { $match.Groups[1].Value.Trim() } else { $null }
}

function Expand-MatrixName([string] $Template, $Cell) {
    [regex]::Replace($Template, '\$\{\{ matrix\.(\w+) \}\}', { param($m) [string] $Cell[$m.Groups[1].Value] })
}

function Get-JobSteps([string] $Job) {
    @([regex]::Split($Job, '(?m)^(?=      - )') | Select-Object -Skip 1)
}

# Returns what makes a debugging session unsafe or misplaced.
function Get-DebugSessionProblem([string] $Text, $Jobs) {
    $problems = [Collections.Generic.List[string]]::new()
    $found = 0
    foreach ($name in $Jobs.Keys) {
        foreach ($step in Get-JobSteps $Jobs[$name]) {
            if (!$step.Contains($script:Tmate)) { continue }
            $found++
            if ($name -cne 'matrix') { $problems.Add("${name}: a debugging session belongs only in the matrix") }
            if ($step -cnotmatch "uses: $([regex]::Escape($script:Tmate))@[0-9a-f]{40} #") {
                $problems.Add('a debugging session must be pinned to a full commit SHA')
            }
            if (!$step.Contains('limit-access-to-actor: true')) { $problems.Add('a debugging session must be limited to the actor') }
            if ($step -cnotmatch '(?m)^        timeout-minutes: \d+$') { $problems.Add('a debugging session needs its own time limit') }
            $condition = Get-StepField $step 'if'
            if (!$condition) { $condition = '' }
            if (!$condition.Contains("github.event_name == 'workflow_dispatch'") -or !$condition.Contains('matrix.tmate ==')) {
                $problems.Add('a debugging session runs only on a dispatch, on the leg the plan chose')
            }
        }
    }
    if ($found -ne 2) { $problems.Add('the matrix must offer a debugging session before the tests and after a failure') }
    if ((Get-JobField $Jobs['matrix'] 'timeout-minutes') -cne "`${{ matrix.tmate == 'off' && 20 || 50 }}") {
        $problems.Add('matrix: the job must cap its time and give the debugging leg more')
    }
    if (!$Jobs['plan'].Contains('TMATE: ${{ inputs.tmate }}') -or !$Jobs['plan'].Contains('-Tmate "${TMATE}"')) {
        $problems.Add('plan: must pass the tmate input through env')
    }
    $problems.ToArray()
}

# Returns what ci.yml does that breaks the plan or the release binding.
function Test-CiWorkflow([string] $Text, $Manifest = (Read-MatrixManifest)) {
    $problems = [Collections.Generic.List[string]]::new()
    $jobs = Get-WorkflowJobs $Text
    foreach ($needed in 'plan', 'port', 'matrix', 'reject', 'reject-old-daemon', 'gate') {
        if (!$jobs.Contains($needed)) { $problems.Add("${needed}: missing job") }
    }
    if ($problems.Count) { return $problems.ToArray() }
    $full = New-MatrixPlan -Manifest $Manifest -EventName workflow_dispatch -Scope full

    $names = [ordered]@{
        'plan'                              = Get-JobField $jobs['plan'] 'name'
        'build and pack PowerShell modules' = Get-JobField $jobs['port'] 'name'
        'powershell gate'                   = Get-JobField $jobs['gate'] 'name'
    }
    foreach ($expected in $names.Keys) {
        if ($names[$expected] -cne $expected) { $problems.Add("the job named '$($names[$expected])' must be named '$expected'") }
    }
    $rendered = [Collections.Generic.List[string]]::new()
    $rendered.AddRange([string[]] @($names.Values | ForEach-Object { "$_" }))
    $lanes = [ordered]@{ 'matrix' = $full.matrix.include; 'reject' = $full.reject; 'reject-old-daemon' = $full.old_daemon }
    foreach ($job in $lanes.Keys) {
        $template = Get-JobField $jobs[$job] 'name'
        if (!$template) { $template = '' }
        foreach ($cell in $lanes[$job]) { $rendered.Add((Expand-MatrixName $template $cell)) }
    }
    $caller = "$(Get-CallerJobName) / "
    $got = @($rendered | ForEach-Object { "$caller$_" })
    $required = @(Get-RequiredJobs)
    $drift = @(Compare-Object $got $required -CaseSensitive | ForEach-Object { $_.InputObject } | Sort-Object)
    if ($drift.Count) { $problems.Add("job names differ from the release gate's job set: $($drift -join ', ')") }

    $sources = [ordered]@{
        'matrix'            = 'matrix: ${{ fromJSON(needs.plan.outputs.matrix) }}'
        'reject'            = 'matrix: ${{ fromJSON(needs.plan.outputs.reject) }}'
        'reject-old-daemon' = 'matrix: ${{ fromJSON(needs.plan.outputs.old_daemon) }}'
    }
    foreach ($job in $sources.Keys) {
        if (!$jobs[$job].Contains($sources[$job])) { $problems.Add("${job}: the legs must come from the plan") }
        if ((Get-JobField $jobs[$job] 'needs') -cne '[plan, port]') { $problems.Add("${job}: needs must be [plan, port]") }
    }
    if ((Get-JobField $jobs['port'] 'needs') -cne 'plan') { $problems.Add('port: needs must be plan') }
    foreach ($pair in @(@('reject', 'run_reject'), @('reject-old-daemon', 'run_old_daemon'))) {
        if ((Get-JobField $jobs[$pair[0]] 'if') -cne "needs.plan.outputs.$($pair[1]) == 'true'") {
            $problems.Add("$($pair[0]): if must be the plan's $($pair[1]) output")
        }
    }
    if ($null -ne (Get-JobField $jobs['matrix'] 'if')) { $problems.Add('matrix: if may not skip a leg') }

    if ((Get-JobField $jobs['gate'] 'needs') -cne '[plan, port, matrix, reject, reject-old-daemon]') {
        $problems.Add('gate: needs must list the plan, the build, the matrix and both lanes')
    }
    if ((Get-JobField $jobs['gate'] 'if') -cne 'always()') { $problems.Add('gate: if must be always()') }
    if (!$jobs['gate'].Contains('PlanMatrix.ps1 gate') -or !$jobs['gate'].Contains('NEEDS: ${{ toJSON(needs) }}')) {
        $problems.Add('gate: must check the needs context with the plan script')
    }

    $head = $Text.Substring(0, $Text.IndexOf("`njobs:`n", [StringComparison]::Ordinal))
    $call = ''
    if ($head.Contains("`n  workflow_call:`n")) {
        $call = ($head -split "`n  workflow_call:`n", 2)[1]
        $call = ($call -split "`n  workflow_dispatch:", 2)[0]
    }
    if (!$call.Contains("      scope:`n") -or !$call.Contains("        required: true`n")) {
        $problems.Add('workflow_call: the scope input must be required')
    }
    $dispatch = if ($head.Contains("`n  workflow_dispatch:`n")) { ($head -split "`n  workflow_dispatch:`n", 2)[1] } else { '' }
    if (!$dispatch.Contains("        options: ['off', before-tests, on-failure]`n        default: 'off'`n")) {
        $problems.Add("workflow_dispatch: quote 'off' in the tmate options and default, which YAML reads as the boolean false")
    }
    foreach ($name in 'scope', 'tmux-ref', 'pwsh', 'tmate') {
        if ($dispatch -cnotmatch "(?m)^      $([regex]::Escape($name)):$") { $problems.Add("workflow_dispatch: missing the $name input") }
    }

    $number = 0
    foreach ($line in $Text -split "`n") {
        $number++
        $passedThroughEnv = $line -cmatch '^\s+[A-Z_]+: \$\{\{ inputs\.[a-z-]+ \}\}$'
        if ($line.Contains('inputs.') -and !$passedThroughEnv -and !$line.TrimStart().StartsWith('#')) {
            $problems.Add("line ${number}: pass an input to a script through env")
        }
    }

    $problems.AddRange([string[]] @(Get-DebugSessionProblem $Text $jobs))
    $group = "group: powershell-`${{ github.ref }}`${{ github.event_name == 'workflow_dispatch' && format('-{0}', github.run_id) || '' }}"
    if (!$Text.Contains("`n  $group`n")) { $problems.Add("concurrency: add github.run_id to a dispatch run's group") }
    if (!$Text.Contains("`n  cancel-in-progress: true`n")) { $problems.Add('concurrency: a superseded push must still be cancelled') }
    foreach ($each in @($Manifest.supported) + @($Manifest.rejected) + @($Manifest.oldDaemon)) {
        if ($Text.Contains($each.commit)) { $problems.Add("the source commit of tmux $($each.tmux) belongs in the manifest") }
    }
    if ($Text.Contains('autogen.sh')) { $problems.Add('ci: build tmux with the shared build-tmux action, not a script') }
    foreach ($each in @($Manifest.supported) + @($Manifest.development)) {
        if ($Text.Contains("'$($each.tmux)'")) { $problems.Add("tmux $($each.tmux) belongs in the manifest") }
    }
    $problems.ToArray()
}

# Returns what release.yml does that stops a release proving the full set itself.
function Test-ReleaseWorkflow([string] $Text) {
    $problems = [Collections.Generic.List[string]]::new()
    $jobs = Get-WorkflowJobs $Text
    foreach ($needed in 'ci', 'gallery') {
        if (!$jobs.Contains($needed)) { $problems.Add("${needed}: missing job") }
    }
    if ($problems.Count) { return $problems.ToArray() }
    $caller = $jobs['ci']
    if ((Get-JobField $caller 'uses') -cne './.github/workflows/ci.yml') {
        $problems.Add('ci: the release must call the CI workflow of this commit')
    }
    if (!("`n$caller").Contains("`n      scope: full")) { $problems.Add('ci: the release must call the CI workflow at scope full') }
    if ($null -ne (Get-JobField $caller 'name') -or (Get-CallerJobName) -cne 'ci') {
        $problems.Add('ci: the calling job must keep the name the job set expects')
    }
    if ((Get-JobField $jobs['gallery'] 'needs') -cne 'ci') { $problems.Add('gallery: it must wait for the CI it called') }
    if ($Text.Contains('ci_run_id')) { $problems.Add('a release must not take the ID of a run someone else dispatched') }
    if ($Text.Contains('run-id:')) { $problems.Add('gallery: the packages must come from this run') }
    if (!$jobs['gallery'].Contains('CI_RUN_ID: ${{ github.run_id }}')) { $problems.Add('gallery: the provenance check must read this run') }
    if (!$jobs['gallery'].Contains('scripts/release-source/ReleaseSource.ps1') -or !$jobs['gallery'].Contains('-Commit "${GITHUB_SHA}"')) {
        $problems.Add('gallery: a release tag must name the commit that was tested')
    }
    if ($Text.Contains('merge-base')) { $problems.Add('gallery: a release tag may not be an ancestor of the tested commit') }
    foreach ($name in 'ci', 'gallery') {
        if (!$jobs[$name].Contains("github.ref == 'refs/heads/master'")) { $problems.Add("${name}: a release runs from master only") }
    }
    $problems.ToArray()
}

# Lists each `run` script line as an object with its line number, job, step and text.
function Get-RunLine([string] $Text) {
    $lines = $Text -split "`n"
    $found = [Collections.Generic.List[object]]::new()
    $job = $null
    $step = $null
    $inJobs = $false
    $index = 0
    while ($index -lt $lines.Count) {
        $line = $lines[$index]
        $index++
        $inJobs = $inJobs -or $line -ceq 'jobs:'
        $header = [regex]::Match($line, '^  ([A-Za-z0-9_-]+):\s*$')
        if ($inJobs -and $header.Success) { $job = $header.Groups[1].Value; $step = $null }
        $named = [regex]::Match($line, '^\s*- name: (.*)$')
        if ($named.Success) { $step = $named.Groups[1].Value.Trim() }
        $start = [regex]::Match($line, '^(\s*)(- )?run:\s*(.*)$')
        if (!$start.Success) { continue }
        if ($start.Groups[2].Success) { $step = $null }
        $indent = $start.Groups[1].Length + $(if ($start.Groups[2].Success) { 2 } else { 0 })
        if ([regex]::IsMatch($start.Groups[3].Value, '^[|>][+-]?\d*\s*(#.*)?$')) {
            while ($index -lt $lines.Count -and
                (!$lines[$index].Trim() -or ($lines[$index].Length - $lines[$index].TrimStart().Length) -gt $indent)) {
                $found.Add([pscustomobject]@{ Number = $index + 1; Job = $job; Step = $step; Line = $lines[$index] })
                $index++
            }
        } else {
            $found.Add([pscustomobject]@{ Number = $index; Job = $job; Step = $step; Line = $start.Groups[3].Value.TrimStart('''', '"') })
        }
    }
    @($found | Where-Object { !$_.Line.TrimStart().StartsWith('#') })
}

function Get-Where($Row) {
    $place = if ($Row.Job) { "job $($Row.Job), " } else { '' }
    $place + $(if ($Row.Step) { "step '$($Row.Step)'" } else { 'an unnamed step' })
}

$script:RawApt = [regex]::new(
    '(?:^|[;&|(`])\s*(?:\w+=\S*\s+)*' +
    '(?:(?:sudo|env|time|timeout|nice)\s+(?:(?:-\S+|\w+=\S*|\d+[smh]?)\s+)*)*' +
    '(apt(?:-get)?)(?![\w./-])')

# Returns each `run` line that calls apt or apt-get without the shared action.
function Get-RawAptProblem([string] $Path, [string] $Text) {
    foreach ($row in Get-RunLine $Text) {
        $call = $script:RawApt.Match($row.Line.Trim())
        if ($call.Success) {
            "${Path}:$($row.Number): $(Get-Where $row) calls $($call.Groups[1].Value) directly; use libtmux/.github/actions/apt-get"
        }
    }
}

# Returns each `run` line that starts Python, and each setup-python step.
function Get-PythonProblem([string] $Path, [string] $Text) {
    foreach ($row in Get-RunLine $Text) {
        if ($row.Line -cmatch '(^|[\s;&|(`/])python3?(\s|$)') {
            "${Path}:$($row.Number): $(Get-Where $row) starts Python; write the step in PowerShell"
        }
    }
    $number = 0
    foreach ($line in $Text -split "`n") {
        $number++
        if ($line -cmatch '^\s*(- )?uses: actions/setup-python@') { "${Path}:${number}: sets up Python; no step needs it" }
    }
}

# Returns each use of a libtmux/.github action that is not pinned to a full commit.
function Get-UnpinnedActionProblem([string] $Path, [string] $Text) {
    $number = 0
    foreach ($line in $Text -split "`n") {
        $number++
        $use = [regex]::Match($line, '^\s*(?:- )?uses: libtmux/\.github/actions/([\w-]+)@(\S*)')
        if ($use.Success -and $use.Groups[2].Value -cnotmatch '^[0-9a-f]{40}$') {
            "${Path}:${number}: the $($use.Groups[1].Value) action must be pinned to a full commit SHA"
        }
    }
}

# Returns every problem of every workflow in a repository checkout.
function Test-RepositoryWorkflows([string] $Root) {
    $workflows = Join-Path $Root '.github/workflows'
    $problems = [Collections.Generic.List[string]]::new()
    $ci = Get-Content -LiteralPath (Join-Path $workflows 'ci.yml') -Raw
    $manifest = Read-MatrixManifest (Join-Path $Root 'scripts/plan-matrix/matrix.json')
    foreach ($problem in Test-CiWorkflow $ci $manifest) { $problems.Add("ci.yml: $problem") }
    foreach ($problem in Test-ReleaseWorkflow (Get-Content -LiteralPath (Join-Path $workflows 'release.yml') -Raw)) {
        $problems.Add("release.yml: $problem")
    }
    foreach ($file in Get-ChildItem -LiteralPath $workflows -Filter '*.yml') {
        $text = Get-Content -LiteralPath $file.FullName -Raw
        $path = ".github/workflows/$($file.Name)"
        $found = @(Get-RawAptProblem $path $text)
        $found += @(Get-PythonProblem $path $text)
        $found += @(Get-UnpinnedActionProblem $path $text)
        foreach ($problem in $found) {
            if ($problem) { $problems.Add($problem) }
        }
    }
    $problems.ToArray()
}

Export-ModuleMember -Function Get-WorkflowJobs, Test-CiWorkflow, Test-ReleaseWorkflow, Get-RawAptProblem,
Get-PythonProblem, Get-UnpinnedActionProblem, Test-RepositoryWorkflows
