param([Parameter(Mandatory)] [string] $ModuleRoot)

# Integration: captured graphs and contradictory reads use only an owned endpoint.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $ModuleRoot 'LibTmux/0.1.0/LibTmux.psd1')
. "$PSScriptRoot/support/OwnedTmux.ps1"

function Assert-Snapshot([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw $Message }
}

function Assert-CapturedGraph($Snapshot) {
    foreach ($session in $Snapshot.Sessions) {
        Assert-Snapshot ([object]::ReferenceEquals($Snapshot, $session.Server)) 'Session lost its captured root.'
        Assert-Snapshot (@($session.Windows | Where-Object {
                    [object]::ReferenceEquals($_, $session.ActiveWindow)
                }).Count -eq 1) 'Active window lost its captured placement.'
        Assert-Snapshot ([object]::ReferenceEquals($session.ActiveWindow, $session.ActivePane.Window)) 'Active pane lost its window placement.'
    }
    foreach ($window in $Snapshot.Windows) {
        Assert-Snapshot ([object]::ReferenceEquals($Snapshot, $window.Server)) 'Window lost its captured root.'
        Assert-Snapshot (@($Snapshot.Sessions | Where-Object {
                    [object]::ReferenceEquals($_, $window.Session)
                }).Count -eq 1) 'Window lost its captured session.'
        Assert-Snapshot (@($window.Panes | Where-Object {
                    [object]::ReferenceEquals($_, $window.ActivePane)
                }).Count -eq 1) 'Active pane lost its captured instance.'
        foreach ($pane in $window.Panes) {
            Assert-Snapshot ([object]::ReferenceEquals($window, $pane.Window) -and
                [object]::ReferenceEquals($window.Session, $pane.Session) -and
                [object]::ReferenceEquals($Snapshot, $pane.Server)) 'Pane lost its captured parents.'
        }
        foreach ($linked in $window.LinkedSessions) {
            Assert-Snapshot ([object]::ReferenceEquals($Snapshot, $linked.Server)) 'Linked session escaped the captured root.'
        }
    }
}

$retained = [Collections.Generic.List[object]]::new()
Invoke-WithOwnedTmux {
    param($fixture)
    $trace = Join-Path $fixture.DirectoryPath 'calls'
    $arm = Join-Path $fixture.DirectoryPath 'change-before-windows'
    $wrapper = Join-Path $fixture.DirectoryPath 'tmux'
    $quotedTmux = "'" + $fixture.TmuxPath.Replace("'", "'\''") + "'"
    @"
#!/bin/sh
printf '%s\n' call >> '$trace'
case "`$*" in
  *list-windows*)
    if [ -f '$arm' ]; then
      rm '$arm'
      $quotedTmux -S '$($fixture.SocketPath)' new-window -d -t '`$0:' 'exec /bin/sh' || exit 1
    fi
    ;;
esac
exec $quotedTmux "`$@"
"@ | Set-Content -LiteralPath $wrapper
    [IO.File]::SetUnixFileMode($wrapper, [IO.UnixFileMode]::UserRead -bor
        [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)
    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $wrapper
    foreach ($depth in @('Server', 'Sessions', 'Windows', 'Panes')) {
        $capture = $server | LibTmux\Get-TmuxSnapshot -Depth $depth
        Assert-Snapshot ($capture.PSObject.Properties.Name -contains 'SnapshotMetadata') 'Snapshot provenance is unavailable.'
        $metadata = $capture.SnapshotMetadata
        Assert-Snapshot ($metadata.Depth.ToString() -ceq $depth -and $metadata.Generation -eq $capture.Generation -and
            $metadata.Elapsed -ge [TimeSpan]::Zero -and $metadata.StartedAtUtc.Offset -eq [TimeSpan]::Zero -and
            $metadata.CompletedAtUtc.Offset -eq [TimeSpan]::Zero) 'Snapshot provenance lost depth, generation or clock data.'
        Assert-Snapshot ($null -eq $server.SnapshotMetadata) 'Capture mutated the original provenance.'
    }

    $null = Invoke-OwnedTmux $fixture -Arguments @('link-window', '-d', '-s', '$0:0', '-t', '$0:5')
    $null = Invoke-OwnedTmux $fixture -Arguments @('split-window', '-d', '-t', '%0', 'exec /bin/sh')
    $null = Invoke-OwnedTmux $fixture -Arguments @('new-session', '-d', '-s', 'graph-other', 'exec /bin/sh')
    $null = Invoke-OwnedTmux $fixture -Arguments @('link-window', '-d', '-s', '$0:0', '-t', 'graph-other:5')
    $null = Invoke-OwnedTmux $fixture -Arguments @('select-window', '-t', '$0:5')
    Register-OwnedTmuxPane $fixture
    $graph = $server | LibTmux\Get-TmuxSnapshot
    $later = $graph | LibTmux\Get-TmuxSnapshot
    $before = [IO.File]::ReadAllLines($trace).Length
    Assert-CapturedGraph $graph
    Assert-CapturedGraph $later
    $selected = @($graph.Panes | Where-Object { $_.Window.Index -eq 5 -and $_.Session.Id.ToString() -ceq '$0' })
    Assert-Snapshot ($selected.Count -eq 2 -and $selected[0].Window.Panes.Count -eq 2 -and
        $selected[0].Window.LinkedSessions.Count -eq 2 -and $graph.Windows.Count -eq 4) 'Local filtering pruned the captured graph.'
    Assert-Snapshot (![object]::ReferenceEquals($graph, $later) -and
        ![object]::ReferenceEquals($graph.Panes[0], $later.Panes[0])) 'Recapture reused an earlier graph.'
    Assert-Snapshot ([IO.File]::ReadAllLines($trace).Length -eq $before) 'Captured navigation performed tmux I/O.'

    [IO.File]::WriteAllText($arm, '')
    $failure = $null
    $output = [Collections.Generic.List[object]]::new()
    try {
        $server | LibTmux\Get-TmuxSnapshot -Depth Windows -ErrorAction Stop | ForEach-Object { $output.Add($_) }
    } catch { $failure = $_ } finally { Register-OwnedTmuxPane $fixture }
    Assert-Snapshot ($null -ne $failure -and $output.Count -eq 0) 'Contradictory reads published a graph.'
    Assert-Snapshot ($failure.FullyQualifiedErrorId -like 'Tmux.SnapshotFailed,*' -and
        $failure.Exception -is [LibTmux.InconsistentSnapshotException] -and
        $failure.Exception.Dispatch -eq [LibTmux.TmuxDispatchState]::Dispatched -and
        $failure.CategoryInfo.Category -eq [Management.Automation.ErrorCategory]::InvalidData -and
        [object]::ReferenceEquals($failure.TargetObject, $server)) 'Snapshot failure lost its native context.'
    Assert-Snapshot ($graph.Windows.Count -eq 4) 'Failed recapture changed an earlier graph.'
    $retained.Add($graph)
    $retained.Add($later)
}

foreach ($graph in $retained) {
    Assert-CapturedGraph $graph
    Assert-Snapshot ($graph.SnapshotMetadata.Depth -eq [LibTmux.SnapshotDepth]::Panes) 'Provenance changed after teardown.'
}
'PASS: installed snapshot provenance, exact captured parents, repeated placements, local navigation and contradictory-read errors'
