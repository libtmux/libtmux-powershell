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
    $quotedTmux = "'" + $fixture.TmuxPath.Replace("'", "'\''") + "'"
    @"
#!/bin/sh
printf '%s\n' dispatch >> '$trace'
case "`$*" in
    *new-window*)
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
    $hostMarker = Join-Path $fixture.DirectoryPath 'host-effect'
    @'
session_name: reviewed
before_script: printf reviewed > host-effect
options:
  default-command: exec /bin/cat
  base-index: '4'
windows:
  - window_name: editor
    focus: true
    layout: even-horizontal
    panes:
      - options:
          '@role': editor
      - focus: true
'@ | Set-Content -LiteralPath $source
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
        $hostAction[0].Request.MaxOutputBytes -eq 256 -and $hostAction[0].Request.WorkingDirectory -ceq $fixture.DirectoryPath) 'host action lost reviewed bounds or origin'
    Remove-Item -LiteralPath $source
    $beforePreview = [IO.File]::ReadAllText($trace)
    $transcript = Join-Path $fixture.DirectoryPath 'preview.txt'
    $null = Start-Transcript -Path $transcript
    try {
        Assert-WorkspaceApply (@($plan | LibTmux.Workspace\Invoke-TmuxWorkspace -WhatIf).Count -eq 0) 'preview emitted a fake result'
    } finally { $null = Stop-Transcript }
    $preview = [IO.File]::ReadAllText($transcript)
    foreach ($value in @($wrapper, $fixture.SocketPath, 'reviewed') + @($plan.Actions.Kind) + @($plan.CompensationActions.Kind)) {
        Assert-WorkspaceApply ($preview.Contains($value.ToString(), [StringComparison]::Ordinal)) "preview omitted $value"
    }
    Assert-WorkspaceApply ([IO.File]::ReadAllText($trace) -ceq $beforePreview -and !(Test-Path -LiteralPath $hostMarker)) 'preview dispatched tmux, host work or cleanup'

    $result = $plan | LibTmux.Workspace\Invoke-TmuxWorkspace -Confirm:$false
    Register-OwnedTmuxPane $fixture
    Assert-WorkspaceApply ($result -is [LibTmux.Workspace.WorkspaceResult] -and $result.Session.Name -ceq 'reviewed' -and
        $result.Windows.Count -eq 1 -and $result.Windows[0].Index -eq 4 -and
        [IO.File]::ReadAllText($hostMarker) -ceq 'reviewed') 'exact reviewed application lost native result, layout order or host action'
    Assert-WorkspaceApply ($result.Journal.Count -eq $plan.Actions.Count) 'successful action journal is incomplete'
    for ($index = 0; $index -lt $plan.Actions.Count; $index++) {
        Assert-WorkspaceApply ([object]::ReferenceEquals($result.Journal[$index].Action, $plan.Actions[$index]) -and
            $result.Journal[$index].State -eq [LibTmux.Workspace.WorkspaceActionState]::Completed) 'application replanned or lost a completed action'
    }
    $panes = @($result.Windows[0] | LibTmux\Get-TmuxPane)
    Assert-WorkspaceApply ($panes.Count -eq 2 -and [Math]::Abs($panes[0].Width - $panes[1].Width) -le 1 -and
        $panes[0].Height -eq $panes[1].Height -and
        ($panes[0] | LibTmux\Get-TmuxOption -Name '@role').Value.Raw -ceq 'editor' -and
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
