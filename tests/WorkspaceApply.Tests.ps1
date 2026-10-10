param([Parameter(Mandatory)] [string] $ModuleRoot)

# Outer integration: reviewed application and cancellation require owned tmux.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path $ModuleRoot).Path
$coreModule = Join-Path $root 'LibTmux/0.1.0/LibTmux.psd1'
$workspaceModule = Join-Path $root 'LibTmux.Workspace/0.1.0/LibTmux.Workspace.psd1'
Import-Module $coreModule
Import-Module $workspaceModule
. "$PSScriptRoot/support/OwnedTmux.ps1"

function Assert-WorkspaceApply([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Workspace apply: $Message" }
}

foreach ($name in @('Get-TmuxWorkspacePlan', 'Invoke-TmuxWorkspace')) {
    Assert-WorkspaceApply ($null -ne (Get-Command "LibTmux.Workspace\$name" -ErrorAction SilentlyContinue)) "installed module has no $name"
}

Invoke-WithOwnedTmux {
    param($fixture)
    $trace = Join-Path $fixture.DirectoryPath 'workspace-dispatch'
    $wrapper = Join-Path $fixture.DirectoryPath 'workspace-tmux'
    $arm = Join-Path $fixture.DirectoryPath 'block-workspace'
    $clientPath = Join-Path $fixture.DirectoryPath 'workspace-client'
    $readinessArm = Join-Path $fixture.DirectoryPath 'signal-before-readiness-wait'
    $readinessSignal = Join-Path $fixture.DirectoryPath 'readiness-channel-signalled'
    $quotedTmux = "'" + $fixture.TmuxPath.Replace("'", "'\''") + "'"
    $quotedSocket = "'" + $fixture.SocketPath.Replace("'", "'\''") + "'"
    @"
#!/bin/sh
printf '%s\n' dispatch >> '$trace'
case "`$*" in
    *new-window*)
        if [ -f '$readinessArm' ]; then
            rm '$readinessArm'
            channel=''
            for arg in "`$@"; do
                case "`$arg" in
                    LIBTMUX_WORKSPACE_READY=*) channel=`${arg#LIBTMUX_WORKSPACE_READY=} ;;
                esac
            done
            if [ -z "`$channel" ]; then printf 'missing readiness channel\n' >&2; exit 42; fi
            $quotedTmux "`$@"
            status=`$?
            if [ "`$status" -ne 0 ]; then exit "`$status"; fi
            $quotedTmux -S $quotedSocket wait-for -S "`$channel"
            status=`$?
            if [ "`$status" -ne 0 ]; then exit "`$status"; fi
            printf '%s' "`$channel" > '$readinessSignal'
            exit 0
        fi
        if [ -f '$arm' ]; then
            rm '$arm'
            printf '%s\n' "`$`$" > '$clientPath'
            exec $quotedTmux -S '$($fixture.SocketPath)' wait-for -S workspace-dispatch-ready ';' wait-for workspace-dispatch-blocked
        fi
        ;;
esac
exec $quotedTmux "`$@"
"@ | Set-Content -LiteralPath $wrapper
    [IO.File]::SetUnixFileMode($wrapper, [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)
    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $wrapper
    $source = Join-Path $fixture.DirectoryPath 'workspace.yaml'
    $sessionDirectory = Join-Path $fixture.DirectoryPath 'session-cwd'
    $null = New-Item -ItemType Directory -Path $sessionDirectory
    $hostMarker = Join-Path $sessionDirectory 'host-effect'
    $sensitive = 'review-' + [Guid]::NewGuid().ToString('N')
    $yaml = @"
session_name: reviewed
start_directory: session-cwd
before_script: >-
  $quotedTmux -S $quotedSocket has-session -t '=reviewed' && printf '%s' "`$PWD" && printf '$sensitive' > host-effect
environment:
  REVIEW_TOKEN: '$sensitive'
options:
  default-command: exec /bin/cat
  base-index: '4'
global_options:
  '@workspace-global': '$sensitive'
windows:
  - window_name: editor
    focus: true
    layout: even-horizontal
    options_after:
      '@workspace-after': '$sensitive'
    panes:
      - options:
          '@role': '$sensitive'
        shell_command: echo '$sensitive'
      - focus: true
"@
    $yaml | Set-Content -LiteralPath $source
    $workspace = (LibTmux.Workspace\Import-TmuxWorkspace -LiteralPath $source).Resolve($fixture.DirectoryPath, $null)
    [IO.File]::WriteAllText($trace, '')
    foreach ($arguments in @(
        @{ ReadinessTimeout = 0 }, @{ HostScriptTimeout = [double]::NaN },
        @{ CleanupTimeout = [double]::PositiveInfinity }, @{ CleanupTimeout = 86401 },
        @{ MaxHostOutputBytes = 0 }, @{}
    )) {
        $failure = $null
        try { $workspace | LibTmux.Workspace\Get-TmuxWorkspacePlan -Server $server @arguments } catch { $failure = $_ }
        Assert-WorkspaceApply ($null -ne $failure) 'invalid policy or missing host opt-in was accepted'
    }
    Assert-WorkspaceApply ([IO.File]::ReadAllText($trace).Length -eq 0 -and !(Test-Path -LiteralPath $hostMarker)) 'invalid planning dispatched tmux or host work'

    $plan = $workspace | LibTmux.Workspace\Get-TmuxWorkspacePlan -Server $server -AllowHostScripts -CompensateOnFailure -ReadinessTimeout 0.5 -HostScriptTimeout 2 -MaxHostOutputBytes 256 -CleanupTimeout 0.5
    Assert-WorkspaceApply ($plan -is [LibTmux.Workspace.WorkspacePlan] -and
        [object]::ReferenceEquals($plan.Endpoint, $server) -and $plan.SessionName -ceq 'reviewed' -and
        $plan.ReadinessTimeout -eq [TimeSpan]::FromSeconds(0.5) -and
        $plan.CleanupTimeout -eq [TimeSpan]::FromSeconds(0.5)) 'planning replaced the native endpoint or lost seconds/policy'
    $hostAction = @($plan.Actions | Where-Object Kind -eq RunHostScript)
    Assert-WorkspaceApply ($hostAction.Count -eq 1 -and $hostAction[0].Request.Timeout -eq [TimeSpan]::FromSeconds(2) -and
        $hostAction[0].Request.MaxOutputBytes -eq 256 -and $hostAction[0].Request.WorkingDirectory -ceq $sessionDirectory) 'host action lost reviewed bounds or session directory'
    $paneText = @($plan.Actions | Where-Object Kind -eq SendText)
    $paneOption = @($plan.Actions | Where-Object { $_.Kind -eq 'SetOption' -and $_.Request.Name -eq '@role' })
    $globalOption = @($plan.Actions | Where-Object { $_.Kind -eq 'SetOption' -and $_.Request.Global })
    Assert-WorkspaceApply ($globalOption.Count -eq 1 -and
        $globalOption[0].Request.Scope -eq [LibTmux.OptionScope]::Session) 'global option lost its explicit native scope'
    Assert-WorkspaceApply ($hostAction[0].Request.Script.Contains($sensitive) -and
        $hostAction[0].Request.Environment['REVIEW_TOKEN'] -ceq $sensitive -and
        $paneText.Count -eq 1 -and $paneText[0].Request.Text.Contains($sensitive) -and
        $paneOption.Count -eq 1 -and $paneOption[0].Request.Value -ceq $sensitive) 'exact requests lost plan values'
    $review = $plan.Actions | Out-String -Width 240
    Assert-WorkspaceApply (!$review.Contains($sensitive) -and
        $review.Contains('RunHostScript') -and $review.Contains('window:0/pane:0') -and
        $review.Contains('layout=even-horizontal') -and $review.Contains('timeout=2s') -and
        $review.Contains('output=256B') -and $review.Contains('env=1') -and
        $review.Contains('path=[redacted]') -and $review.Contains('@role') -and
        $review.Contains('script=[redacted]') -and $review.Contains('text=[redacted]') -and
        $review.Contains('scope=Session') -and $review.Contains('global=True') -and
        $review.Contains('scope=Owner') -and $review.Contains('global=False') -and
        $review.Contains('value=[redacted]')) 'default plan review leaked values or omitted safe context'
    $narrowReview = $plan.Actions | Out-String -Width 80
    Assert-WorkspaceApply (!$narrowReview.Contains($sensitive) -and
        $narrowReview.Contains('script=[redacted]') -and
        $narrowReview.Contains('layout=even-horizontal') -and
        $narrowReview.Contains('value=[redacted]')) 'narrow plan review hid safe action details'
    $compensationReview = $plan.CompensationActions | Out-String -Width 240
    Assert-WorkspaceApply (!$compensationReview.Contains($sensitive) -and
        $compensationReview.Contains('UnlinkWindow')) 'compensation review leaked values or omitted cleanup'
    $cooperative = $workspace | LibTmux.Workspace\Get-TmuxWorkspacePlan -Server $server -AllowHostScripts -Readiness Cooperative -ReadinessTimeout 0.5
    $readinessReview = $cooperative.Actions | Out-String -Width 80
    Assert-WorkspaceApply (!$readinessReview.Contains($sensitive) -and
        $readinessReview.Contains('WaitForReadiness') -and
        $readinessReview.Contains('timeout=0.5s')) 'cooperative readiness was not visible in plan review'
    $expandedYaml = "$yaml`n  - window_name: logs`n    panes:`n      - shell_command: echo '$sensitive'`n      - shell_command: echo '$sensitive'"
    $expandedWorkspace = (LibTmux.Workspace\Import-TmuxWorkspace -Yaml $expandedYaml).Resolve($fixture.DirectoryPath, $null)
    $expandedPlan = $expandedWorkspace | LibTmux.Workspace\Get-TmuxWorkspacePlan -Server $server -AllowHostScripts -CompensateOnFailure
    Assert-WorkspaceApply ($expandedPlan.Actions.Count -gt $plan.Actions.Count -and
        @($expandedPlan.Actions | Where-Object Kind -eq SplitPane).Count -eq 2 -and
        @($expandedPlan.Actions | Where-Object Kind -eq SendText).Count -eq 3 -and
        (@($plan.Actions.Kind | Select-Object -Unique) -join ',') -ceq
        (@($expandedPlan.Actions.Kind | Select-Object -Unique) -join ',')) 'preview fixtures need different pane and command counts with the same action kinds'
    Remove-Item -LiteralPath $source
    $beforePreview = [IO.File]::ReadAllText($trace)
    foreach ($case in @(@{ Name = 'original'; Plan = $plan }, @{ Name = 'expanded'; Plan = $expandedPlan })) {
        $transcript = Join-Path $fixture.DirectoryPath "preview-$($case.Name).txt"
        $null = Start-Transcript -Path $transcript
        try {
            Assert-WorkspaceApply (@($case.Plan | LibTmux.Workspace\Invoke-TmuxWorkspace -WhatIf).Count -eq 0) 'preview emitted a fake result'
        } finally { $null = Stop-Transcript }
        $preview = [IO.File]::ReadAllText($transcript)
        Assert-WorkspaceApply (!$preview.Contains($sensitive)) 'WhatIf leaked a sensitive request value'
        foreach ($value in @($wrapper, $fixture.SocketPath, 'reviewed')) {
            Assert-WorkspaceApply ($preview.Contains($value, [StringComparison]::Ordinal)) "preview omitted $value"
        }
        $lastPosition = -1
        for ($index = 0; $index -lt $case.Plan.Actions.Count; $index++) {
            $action = $case.Plan.Actions[$index]
            $expected = "$(($index + 1)). $($action.Kind) $($action.Target)"
            if ($action.SourceTarget) { $expected += " <= $($action.SourceTarget)" }
            $position = $preview.IndexOf($expected, $lastPosition + 1, [StringComparison]::Ordinal)
            Assert-WorkspaceApply ($position -gt $lastPosition) "WhatIf omitted or reordered action $expected"
            $lastPosition = $position
        }
        Assert-WorkspaceApply ($preview.Contains('request values redacted', [StringComparison]::Ordinal)) 'WhatIf did not identify redacted requests'
        Assert-WorkspaceApply ($preview.Contains('global options: True', [StringComparison]::Ordinal) -and
            $preview.Contains('scope=Session; global=True', [StringComparison]::Ordinal) -and
            $preview.Contains('scope=Owner; global=False', [StringComparison]::Ordinal)) 'WhatIf hid option scope or server-global effects'
        $lastPosition = $preview.IndexOf('Conditional cleanup (', [StringComparison]::Ordinal)
        Assert-WorkspaceApply ($lastPosition -ge 0) 'WhatIf omitted conditional cleanup section'
        for ($index = 0; $index -lt $case.Plan.CompensationActions.Count; $index++) {
            $action = $case.Plan.CompensationActions[$index]
            $expected = "$(($index + 1)). $($action.Kind) $($action.Target)"
            if ($action.SourceTarget) { $expected += " <= $($action.SourceTarget)" }
            $position = $preview.IndexOf($expected, $lastPosition + 1, [StringComparison]::Ordinal)
            Assert-WorkspaceApply ($position -gt $lastPosition) "WhatIf omitted or reordered conditional cleanup $expected"
            $lastPosition = $position
        }
    }
    Assert-WorkspaceApply ([IO.File]::ReadAllText($trace) -ceq $beforePreview -and !(Test-Path -LiteralPath $hostMarker)) 'preview dispatched tmux, host work or cleanup'

    $result = $plan | LibTmux.Workspace\Invoke-TmuxWorkspace -Confirm:$false
    Register-OwnedTmuxPane $fixture
    Assert-WorkspaceApply ($result -is [LibTmux.Workspace.WorkspaceResult] -and $result.Session.Name -ceq 'reviewed' -and
        $result.Windows.Count -eq 1 -and $result.Windows[0].Index -eq 4 -and
        [IO.File]::ReadAllText($hostMarker) -ceq $sensitive) 'exact reviewed application lost native result, layout order or host action'
    $hostOutcome = @($result.Journal | Where-Object { $_.Action.Kind -eq 'RunHostScript' })
    Assert-WorkspaceApply ($hostOutcome.Count -eq 1 -and
        $hostOutcome[0].Result.StandardOutput -ceq $sessionDirectory) 'host script did not observe the created session and its resolved session directory'
    Assert-WorkspaceApply ($result.Journal.Count -eq $plan.Actions.Count) 'successful action journal is incomplete'
    for ($index = 0; $index -lt $plan.Actions.Count; $index++) {
        Assert-WorkspaceApply ([object]::ReferenceEquals($result.Journal[$index].Action, $plan.Actions[$index]) -and
            $result.Journal[$index].State -eq [LibTmux.Workspace.WorkspaceActionState]::Completed) 'application replanned or lost a completed action'
    }
    $panes = @($result.Windows[0] | LibTmux\Get-TmuxPane)
    Assert-WorkspaceApply ($panes.Count -eq 2 -and [Math]::Abs($panes[0].Width - $panes[1].Width) -le 1 -and
        $panes[0].Height -eq $panes[1].Height -and
        ($panes[0] | LibTmux\Get-TmuxOption -Name '@role').Value.Raw -ceq $sensitive -and
        (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', $panes[1].Id.ToString(), '#{pane_active}')).StdOut.Trim() -ceq '1') 'native pane options, final layout or focus were not applied'
    $staleFailure = $null
    try { $plan | LibTmux.Workspace\Invoke-TmuxWorkspace -Confirm:$false } catch { $staleFailure = $_ }
    Assert-WorkspaceApply ($staleFailure.Exception -is [LibTmux.Workspace.WorkspaceBuildException] -and
        [object]::ReferenceEquals($staleFailure.TargetObject, $plan) -and
        $staleFailure.FullyQualifiedErrorId -like 'Tmux.WorkspaceApplyFailed,*') 'stale application replanned or lost its native error'

    $reuse = $workspace | LibTmux.Workspace\Get-TmuxWorkspacePlan -Server $server -ExistingSession Reuse
    $reused = $reuse | LibTmux.Workspace\Invoke-TmuxWorkspace -Confirm:$false
    Assert-WorkspaceApply ($reused.Session.Id -eq $result.Session.Id -and $reused.Windows.Count -eq 0 -and
        $reuse.Actions.Count -eq 1 -and $reuse.Actions[0].Kind -eq [LibTmux.Workspace.WorkspaceActionKind]::ReuseSession) 'reuse ran declaration effects'
    $bad = LibTmux.Workspace\Import-TmuxWorkspace -Yaml @'
session_name: reviewed
windows:
  - window_name: failed-append
    panes:
      - options:
          libtmux-invalid-option: fail
'@
    $append = $bad | LibTmux.Workspace\Get-TmuxWorkspacePlan -Server $server -ExistingSession Append -CompensateOnFailure
    $errors = @()
    $output = @($append | LibTmux.Workspace\Invoke-TmuxWorkspace -Confirm:$false -ErrorAction Continue -ErrorVariable errors 2>$null)
    Assert-WorkspaceApply ($output.Count -eq 0 -and $errors.Count -eq 1) 'failure emitted a partial success result'
    $failure = $errors[0]
    Assert-WorkspaceApply ($failure.Exception -is [LibTmux.Workspace.WorkspaceBuildException] -and
        $failure.FullyQualifiedErrorId -like 'Tmux.WorkspaceApplyFailed,*' -and
        [object]::ReferenceEquals($failure.TargetObject, $append) -and
        $failure.Exception.PartialResult.Session.Id -eq $result.Session.Id -and
        $failure.Exception.Journal.Count -eq $append.Actions.Count -and
        $failure.Exception.Dispatch -ne [LibTmux.TmuxDispatchState]::NotDispatched -and
        $null -ne $failure.Exception.InnerException -and
        @($failure.Exception.CompensationJournal | Where-Object State -eq Completed).Count -gt 0) 'failure lost native cause, partial result, dispatch or compensation journal'
    Assert-WorkspaceApply (@($result.Session | LibTmux\Get-TmuxWindow).Count -eq 1) 'failed append removed the existing window or left its creation'

    $early = LibTmux.Workspace\Import-TmuxWorkspace -Yaml @'
session_name: reviewed
windows:
  - window_name: early-ready
    panes:
      - null
'@
    $earlyPlan = $early | LibTmux.Workspace\Get-TmuxWorkspacePlan -Server $server -ExistingSession Append -Readiness Cooperative -ReadinessTimeout 0.5 -CompensateOnFailure
    [IO.File]::WriteAllText($readinessArm, '')
    $earlyResult = $earlyPlan | LibTmux.Workspace\Invoke-TmuxWorkspace -Confirm:$false
    Register-OwnedTmuxPane $fixture
    try {
        $open = @($earlyResult.Journal | Where-Object { $_.Action.Kind -eq 'OpenReadinessChannel' })
        $wait = @($earlyResult.Journal | Where-Object { $_.Action.Kind -eq 'WaitForReadiness' })
        Assert-WorkspaceApply ($open.Count -eq 1 -and $wait.Count -eq 1 -and
            $open[0].State -eq [LibTmux.Workspace.WorkspaceActionState]::Completed -and
            $wait[0].State -eq [LibTmux.Workspace.WorkspaceActionState]::Completed -and
            (Test-Path -LiteralPath $readinessSignal) -and
            [IO.File]::ReadAllText($readinessSignal) -ceq $open[0].Result -and
            $earlyResult.Windows.Count -eq 1) 'early owned readiness signal was lost before Apply waited'
    } finally {
        if ($earlyResult.Windows.Count -eq 1) {
            $earlyResult.Windows[0] | LibTmux\Remove-TmuxWindow -Confirm:$false -ErrorAction Stop
        }
    }

    $replace = $workspace | LibTmux.Workspace\Get-TmuxWorkspacePlan -Server $server -ExistingSession Replace -AllowHostScripts
    $replacement = $replace | LibTmux.Workspace\Invoke-TmuxWorkspace -Confirm:$false
    Register-OwnedTmuxPane $fixture
    Assert-WorkspaceApply ($replacement.Session.Id -ne $result.Session.Id -and $replacement.Session.Name -ceq 'reviewed') 'explicit replacement reused the old identity'

    $cancelPlan = $bad | LibTmux.Workspace\Get-TmuxWorkspacePlan -Server $server -ExistingSession Append -CompensateOnFailure
    $initial = [Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
    $initial.ImportPSModule(@($coreModule, $workspaceModule))
    $runspace = [RunspaceFactory]::CreateRunspace($initial)
    $pipeline = [PowerShell]::Create()
    $published = [Collections.Concurrent.ConcurrentQueue[object]]::new()
    [IO.File]::WriteAllText($arm, '')
    try {
        $runspace.Open()
        $pipeline.Runspace = $runspace
        $null = $pipeline.AddScript({
                param($Plan, $Published)
                $outputQueue = $Published
                $Plan | LibTmux.Workspace\Invoke-TmuxWorkspace -Confirm:$false | ForEach-Object { $outputQueue.Enqueue($_) }
            }).AddArgument($cancelPlan).AddArgument($published)
        $invocation = $pipeline.BeginInvoke()
        $null = Invoke-OwnedTmux $fixture -Arguments @('wait-for', 'workspace-dispatch-ready')
        $clientId = [int] [IO.File]::ReadAllText($clientPath)
        $null = $fixture.OwnedProcessIds.Add($clientId)
        $stop = $pipeline.BeginStop($null, $null)
        Assert-WorkspaceApply ($stop.AsyncWaitHandle.WaitOne(1000)) 'workspace pipeline did not stop'
        $pipeline.EndStop($stop)
        Assert-WorkspaceApply ($invocation.AsyncWaitHandle.WaitOne(1000)) 'stopped application did not complete'
        try { $null = $pipeline.EndInvoke($invocation) } catch {
            if ($_.Exception.InnerException -isnot [Management.Automation.PipelineStoppedException]) { throw }
        }
        Assert-WorkspaceApply ($published.IsEmpty) 'stopped application emitted success'
        $client = Get-Process -Id $clientId -ErrorAction SilentlyContinue
        if ($client) { $client.Dispose(); throw 'Workspace apply: stopped application retained its native client' }
    } finally {
        $pipeline.Dispose()
        $runspace.Dispose()
        $null = Invoke-OwnedTmux $fixture -Arguments @('wait-for', '-S', 'workspace-dispatch-blocked')
    }
    Assert-WorkspaceApply ([int](Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '#{pid}')).StdOut -eq $fixture.ServerPid) 'workspace application removed the borrowed daemon'
    $null = Invoke-OwnedTmux $fixture -Arguments @('has-session', '-t', '=fixture')
}
'PASS workspace apply: frozen native plans, preview, policies, result journals, failure compensation and owned cancellation'
