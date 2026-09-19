param([Parameter(Mandatory)] [string] $ModuleRoot)

# Integration: installed cmdlets acquire real tmux objects through native pipelines.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $ModuleRoot 'LibTmux/0.1.0/LibTmux.psd1')

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

foreach ($name in @('Connect-TmuxServer', 'Get-TmuxSnapshot', 'Get-TmuxSession', 'Get-TmuxWindow', 'Get-TmuxPane')) {
    Assert-True ($null -ne (Get-Command "LibTmux\$name" -ErrorAction SilentlyContinue)) "Installed module does not export $name."
}

. "$PSScriptRoot/support/OwnedTmux.ps1"
$fieldChecks = [System.Collections.Generic.List[object]]::new()
Invoke-WithOwnedTmux {
    param($fixture)

    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -ConfigurationFile '/dev/null'
    $connected = $server | LibTmux\Connect-TmuxServer
    Assert-True ($connected -is [LibTmux.Server] -and $connected.IsMaterialized) 'Connect did not return a native live server.'
    Assert-True (-not $server.IsMaterialized) 'Connect mutated the original endpoint handle.'

    $sessions = @($server | LibTmux\Get-TmuxSession)
    Assert-True ($sessions.Count -eq 1 -and $sessions[0] -is [LibTmux.Session]) 'Single-session output was not a native session.'
    Assert-True (-not $sessions[0].Windows.IsCaptured) 'Session-only acquisition claimed to capture windows.'
    $windows = @($sessions[0] | LibTmux\Get-TmuxWindow)
    Assert-True ($windows.Count -eq 1 -and $windows[0] -is [LibTmux.Window]) 'Session pipeline did not acquire its window.'
    $panes = @($windows[0] | LibTmux\Get-TmuxPane)
    Assert-True ($panes.Count -eq 1 -and $panes[0] -is [LibTmux.Pane]) 'Window pipeline did not acquire its pane.'
    $fieldChecks.Add(@{
        Pane = $panes[0]
        Command = $panes[0].RawFormatFields['pane_current_command']
        Path = $panes[0].RawFormatFields['pane_current_path']
    })

    $shallow = $server | LibTmux\Get-TmuxSnapshot -Depth Sessions
    Assert-True (-not [object]::ReferenceEquals($server, $shallow)) 'Snapshot reused the input object.'
    Assert-True (-not $server.Sessions.IsCaptured -and $shallow.Sessions.IsCaptured) 'Snapshot mutated the original captured graph.'
    Assert-True (-not $shallow.Windows.IsCaptured) 'Shallow snapshot claimed to capture windows.'
    $unavailable = $false
    try { $null = $shallow.Windows.get_Count() } catch {
        $unavailable = $_.Exception.InnerException -is [LibTmux.IncompleteSnapshotException]
    }
    Assert-True $unavailable 'An uncaptured relation became an empty relation.'

    $null = Invoke-OwnedTmux $fixture -Arguments @('rename-session', '-t', 'fixture', 'Case')
    $null = Invoke-OwnedTmux $fixture -Arguments @('rename-window', '-t', 'Case:0', 'Main')
    $null = Invoke-OwnedTmux $fixture -Arguments @('new-window', '-d', '-t', 'Case:', '-n', 'main', 'exec /bin/sh')
    $null = Invoke-OwnedTmux $fixture -Arguments @('new-session', '-d', '-s', 'case', '-n', 'Other', 'exec /bin/sh')
    $null = Invoke-OwnedTmux $fixture -Arguments @('split-window', '-d', '-t', 'Case:0', 'exec /bin/sh')
    Register-OwnedTmuxPane $fixture

    $sessions = @($server | LibTmux\Get-TmuxSession)
    Assert-True ($sessions.Count -eq 2) 'Multiple sessions were not emitted individually.'
    Assert-True (@($server | LibTmux\Get-TmuxSession -Name 'CASE').Count -eq 0) 'Session selection ignored case.'
    Assert-True (@($server | LibTmux\Get-TmuxSession -Name 'Ca*').Count -eq 0) 'Session selection expanded a wildcard.'
    $session = @($server | LibTmux\Get-TmuxSession -Name 'Case')
    Assert-True ($session.Count -eq 1 -and $session[0].Name -ceq 'Case') 'Exact session selection returned the wrong cardinality.'
    Assert-True (@($server | LibTmux\Get-TmuxSession -Id $session[0].Id.ToString()).Count -eq 1) 'Session ID selection failed.'
    Assert-True (@($server | LibTmux\Get-TmuxWindow).Count -eq 3) 'Server window listing was incomplete.'
    Assert-True (@($session[0] | LibTmux\Get-TmuxWindow).Count -eq 2) 'Window listing escaped its session.'
    $main = @($session[0] | LibTmux\Get-TmuxWindow -Name 'Main')
    Assert-True ($main.Count -eq 1 -and $main[0].Name -ceq 'Main') 'Window selection was not ordinal.'
    Assert-True (@($server | LibTmux\Get-TmuxWindow -Name 'Ma*').Count -eq 0) 'Window selection expanded a wildcard.'
    Assert-True (@($server | LibTmux\Get-TmuxPane).Count -eq 4) 'Server pane listing was incomplete.'
    Assert-True (@($session[0] | LibTmux\Get-TmuxPane).Count -eq 3) 'Pane listing escaped its session.'
    $panes = @($main[0] | LibTmux\Get-TmuxPane)
    Assert-True ($panes.Count -eq 2) 'Pane listing escaped its window.'
    Assert-True (@($server | LibTmux\Get-TmuxPane -Id $panes[0].Id.ToString()).Count -eq 1) 'Pane ID selection failed.'
    Assert-True (@($server | LibTmux\Get-TmuxPane | Select-Object -First 1).Count -eq 1) 'Downstream early exit became a read failure.'
    $snapshot = $shallow | LibTmux\Get-TmuxSnapshot
    Assert-True ($snapshot -is [LibTmux.Server] -and $snapshot.Panes.Count -eq 4) 'Full snapshot did not capture the current graph.'
    Assert-True ($shallow.Sessions.Count -eq 1) 'Refreshing changed a previous snapshot.'

    $bindingFailed = $false
    try { [pscustomobject]@{ Server = $server } | LibTmux\Get-TmuxSession | Out-Null } catch {
        $bindingFailed = $_.FullyQualifiedErrorId -match 'InputObjectNotBound'
    }
    Assert-True $bindingFailed 'An arbitrary object bound through its Server property.'

    $missing = LibTmux\New-TmuxServer -SocketPath (Join-Path $fixture.DirectoryPath 'absent')
    $failure = $null
    $output = [System.Collections.Generic.List[object]]::new()
    try { $missing | LibTmux\Get-TmuxSession | ForEach-Object { $output.Add($_) } } catch { $failure = $_ }
    Assert-True ($null -ne $failure) 'A missing endpoint became an empty successful session list.'
    Assert-True ($output.Count -eq 0) 'A failed acquisition emitted success output.'
    Assert-True ($failure.FullyQualifiedErrorId -like 'Tmux.SessionReadFailed,*') 'Read failure lost its stable error ID.'
    Assert-True ($failure.Exception -is [LibTmux.LibTmuxException]) 'Read failure replaced the core exception.'
    Assert-True ($failure.Exception.Dispatch -is [LibTmux.TmuxDispatchState]) 'Read failure lost core dispatch metadata.'
    $readErrors = @()
    $continued = @(@($missing, $server) | LibTmux\Get-TmuxSession -ErrorAction Continue -ErrorVariable readErrors 2>$null)
    Assert-True ($continued.Count -eq 2) 'An error on one owner stopped the later live owner.'
    Assert-True ($readErrors.Count -eq 1 -and $readErrors[0].TargetObject -eq $missing) 'Per-owner errors did not retain the failed target.'
}

foreach ($check in $fieldChecks) {
    Assert-True ($check.Pane.get_CurrentCommand() -ceq $check.Command) 'Captured command changed after daemon teardown.'
    Assert-True ($check.Pane.get_CurrentPath() -ceq $check.Path) 'Captured path changed after daemon teardown.'
}

'PASS: installed read cmdlets, native pipelines, exact selection, immutable snapshots, and strict errors'
