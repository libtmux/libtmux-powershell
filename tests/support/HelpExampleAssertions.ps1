function Get-HelpExampleAssertion {
    # Each packaged example needs its own outcome assertion, including examples with no output.
    @{
        'LibTmux\New-TmuxServer#1' = @{ ExpectedCount = 1; Isolated = $false; Assert = {
                param($Result, $Context)
                if ($Result[0].IsMaterialized -or $Result[0].ConnectionOptions.SocketPath -cne $Context.Fixture.SocketPath) {
                    throw 'Endpoint example acquired data or selected the wrong socket.'
                }
            } }
        'LibTmux\Connect-TmuxServer#1' = @{ ExpectedCount = 1; Isolated = $false; Assert = {
                param($Result, $Context)
                if (!$Result[0].IsMaterialized -or $Result[0].ConnectionOptions.SocketPath -cne $Context.Fixture.SocketPath) {
                    throw 'Connection example did not materialize the owned endpoint.'
                }
            } }
        'LibTmux\Get-TmuxSnapshot#1' = @{ ExpectedCount = 1; Isolated = $false; Assert = {
                param($Result, $Context)
                if ($Result[0].Panes.Count -ne 1 -or $Result[0].Panes[0].Id.ToString() -cne $Context.PaneId) {
                    throw 'Snapshot example did not capture the fixture pane.'
                }
            } }
        'LibTmux\Get-TmuxSession#1' = @{ ExpectedCount = 1; Isolated = $false; Assert = {
                param($Result)
                if ($Result[0].Name -cne 'fixture') { throw 'Session example selected the wrong fixture session.' }
            } }
        'LibTmux\Get-TmuxWindow#1' = @{ ExpectedCount = 1; Isolated = $false; Assert = {
                param($Result, $Context)
                if ($Result[0].Id.ToString() -cne $Context.WindowId) { throw 'Window example selected the wrong fixture window.' }
            } }
        'LibTmux\Get-TmuxPane#1' = @{ ExpectedCount = 1; Isolated = $false; Assert = {
                param($Result, $Context)
                if ($Result[0].Id.ToString() -cne $Context.PaneId) { throw 'Pane example selected the wrong fixture pane.' }
            } }
        'LibTmux\Update-TmuxPane#1' = @{ ExpectedCount = 1; Isolated = $false; Assert = {
                param($Result, $Context)
                if ($Result[0].Id.ToString() -cne $Context.PaneId -or $Result[0].Title -cne 'help-example-pane') {
                    throw 'Refresh example did not return current fixture metadata.'
                }
            } }
        'LibTmux\Get-TmuxPaneContent#1' = @{ ExpectedCount = 1; Isolated = $false; Assert = {
                param($Result)
                if (!$Result[0].Contains('libtmux-help-example-output')) { throw 'Capture example lost the completed fixture output.' }
            } }
        'LibTmux.Workspace\Import-TmuxWorkspace#1' = @{ ExpectedCount = 1; Isolated = $false; Assert = {
                param($Result)
                if ($Result[0].SessionName -cne 'development') { throw 'Workspace example parsed the wrong session.' }
            } }
        'LibTmux\Invoke-TmuxCommand#1' = @{ ExpectedCount = 1; Isolated = $false; Assert = {
                param($Result, $Context)
                if ($Result[0].ExitCode -ne 0 -or $Result[0].StandardOutputLines.Count -ne 1 -or
                    $Result[0].StandardOutputLines[0] -cne $Context.Version) {
                    throw 'Raw command example did not return a successful version.'
                }
            } }
        'LibTmux\New-TmuxSession#1' = @{ ExpectedCount = 1; Isolated = $true; Expected = 'help-session|work'; Assert = {
                param($Result, $Context, $Expected)
                $actual = Invoke-OwnedTmux $Context.Fixture -Arguments @('display-message', '-p', '-t', $Result[0].Id.ToString(), '#{session_name}|#{window_name}')
                if ($Result[0].Name -cne 'help-session' -or $actual.StdOut.Trim() -cne $Expected) {
                    throw 'Session creation example did not create its named session and initial window.'
                }
            } }
        'LibTmux\New-TmuxWindow#1' = @{ ExpectedCount = 1; Isolated = $true; Assert = {
                param($Result, $Context)
                $actual = Invoke-OwnedTmux $Context.Fixture -Arguments @('display-message', '-p', '-t', $Result[0].Id.ToString(), '#{session_name}|#{window_name}|#{window_index}')
                if ($Result[0].Name -cne 'help-window' -or $actual.StdOut.Trim() -cne 'fixture|help-window|5') {
                    throw 'Window creation example did not create its named window at the requested index.'
                }
            } }
        'LibTmux\Split-TmuxPane#1' = @{ ExpectedCount = 1; Isolated = $true; Assert = {
                param($Result, $Context)
                $target = $Result[0].Id.ToString()
                $actual = Invoke-OwnedTmux $Context.Fixture -Arguments @('display-message', '-p', '-t', $target, '#{pane_width}|#{pane_active}')
                if ($target -ceq $Context.PaneId -or $actual.StdOut.Trim() -cne '20|0') {
                    throw 'Split example did not return a new unselected pane with the requested width.'
                }
            } }
    }
}

function Assert-HelpExampleRegistration($Examples, [hashtable] $Assertions) {
    $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($example in $Examples) {
        if (!$ids.Add($example.Id)) { throw "Duplicate help example ID: $($example.Id)" }
        if (!$Assertions.ContainsKey($example.Id)) { throw "Missing help example assertion: $($example.Id)" }
        $entry = $Assertions[$example.Id]
        if ($entry.Assert -isnot [scriptblock] -or $entry.ExpectedCount -isnot [int] -or
            $entry.ExpectedCount -lt 0 -or $entry.Isolated -isnot [bool]) {
            throw "Invalid help example assertion: $($example.Id)"
        }
    }
    foreach ($id in $Assertions.Keys) {
        if (!$ids.Contains($id)) { throw "Help example assertion has no packaged example: $id" }
    }
}
