function Get-HelpExampleAssertion {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'pane',
        Justification = 'Preparation binds the documented pane variable in the example execution scope.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'server',
        Justification = 'Preparation binds the documented server variable in the example execution scope.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'session',
        Justification = 'Preparation binds the documented session variable in the example execution scope.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'window',
        Justification = 'Preparation binds the documented window variable in the example execution scope.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', 'control',
        Justification = 'Preparation binds the documented control variable in the example execution scope.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Result',
        Justification = 'Zero-output assertions use fixture state and retain the shared result/context callback signature.')]
    param()

    # Each packaged example needs its own outcome assertion, including examples with no output.
    @{
        'LibTmux\Get-TmuxQueryPlan#1' = @{ ExpectedCount = 1; Isolated = $false; Assert = {
                param($Result)
                $plan = $Result[0]
                if ($plan -isnot [LibTmux.Query.QueryPlan[LibTmux.Pane]] -or
                    $plan.DaemonVersion.Raw -cne '3.2a' -or
                    $plan.Pushdown -ne [LibTmux.Query.QueryPushdown]::Require -or
                    $null -eq $plan.PushedPredicate -or $null -ne $plan.ResidualPredicate) {
                    throw 'Plan example did not preserve the native exact pane-ID source plan.'
                }
            } }
        'LibTmux\Invoke-TmuxQuery#1' = @{ ExpectedCount = 1; Isolated = $false; Assert = {
                param($Result, $Context)
                if ($Result[0] -isnot [LibTmux.Pane] -or
                    $Result[0].Id.ToString() -cne $Context.PaneId -or $Result[0].Width -lt 80) {
                    throw 'Source query example did not emit the captured wide pane.'
                }
            } }
        'LibTmux\Invoke-TmuxQuery#2' = @{ ExpectedCount = 1; Isolated = $false; Assert = {
                param($Result, $Context)
                $queryResult = $Result[0]
                if ($queryResult -isnot [LibTmux.Query.QueryResult[LibTmux.Pane]] -or
                    $queryResult.Count -ne 1 -or $queryResult[0].Id.ToString() -cne $Context.PaneId -or
                    $queryResult.Snapshot.Panes.Count -ne 1 -or
                    ![object]::ReferenceEquals($queryResult[0], $queryResult.Snapshot.Panes[0])) {
                    throw 'Result example did not retain matching rows from its complete snapshot.'
                }
            } }
        'LibTmux\New-TmuxQuery#1' = @{ ExpectedCount = 1; Isolated = $false; Assert = {
                param($Result, $Context)
                $query = $Result[0]
                $snapshot = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath | LibTmux\Get-TmuxSnapshot
                $selectedPanes = @($snapshot.Panes | LibTmux\Select-TmuxPane -Query $query)
                if ($query.Version -ne 2 -or $query.Target -ne [LibTmux.Query.QueryTarget]::Pane -or
                    $selectedPanes.Count -ne 1 -or $selectedPanes[0].Width -lt 80 -or
                    ($query | LibTmux\ConvertTo-TmuxQueryJson) -notmatch 'pane_width') {
                    throw 'Query example did not construct the documented native pane-width criterion.'
                }
            } }
        'LibTmux\ConvertTo-TmuxQueryJson#1' = @{ ExpectedCount = 1; Isolated = $false; Assert = {
                param($Result)
                $query = LibTmux\New-TmuxQuery -Json $Result[0]
                if ($query.Version -ne 2 -or $query.Target -ne [LibTmux.Query.QueryTarget]::Pane -or
                    ($query | LibTmux\ConvertTo-TmuxQueryJson) -cne $Result[0] -or $Result[0] -notmatch 'pane_width') {
                    throw 'Query JSON example did not round-trip the documented pane-width criterion.'
                }
            } }
        'LibTmux\Get-TmuxQueryField#1' = @{ ExpectedCount = 1; Isolated = $false; Assert = {
                param($Result)
                if ($Result[0].WireName -cne 'pane_width' -or $Result[0].ScalarPropertyPath -cne 'Width' -or
                    $Result[0].ValueKind -ne [LibTmux.Query.QueryValueKind]::Int64) {
                    throw 'Field discovery example did not return the native numeric Width binding.'
                }
            } }
        'LibTmux\Select-TmuxPane#1' = @{ ExpectedCount = 1; Isolated = $false; Assert = {
                param($Result, $Context)
                if ($Result[0].Id.ToString() -cne $Context.PaneId -or $Result[0].Width -lt 80) {
                    throw 'Pane selection example did not return the captured wide pane.'
                }
            } }
        'LibTmux\Select-TmuxSession#1' = @{ ExpectedCount = 1; Isolated = $false; Assert = {
                param($Result)
                if ($Result[0].Name -cne 'fixture' -or $Result[0].Attached) {
                    throw 'Session selection example did not return the detached fixture session.'
                }
            } }
        'LibTmux\Select-TmuxWindow#1' = @{ ExpectedCount = 1; Isolated = $false; Assert = {
                param($Result, $Context)
                if ($Result[0].Id.ToString() -cne $Context.WindowId -or !$Result[0].IsActive) {
                    throw 'Window selection example did not return the active captured placement.'
                }
            } }
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
        'LibTmux\Get-TmuxServer#1' = @{ ExpectedCount = 1; Isolated = $false; Assert = {
                param($Result, $Context)
                $version = (Invoke-OwnedTmux $Context.Fixture -Arguments @('display-message', '-p', '#{version}')).StdOut.Trim()
                if (!$Result[0].IsMaterialized -or $Result[0].DaemonVersion.Raw -cne $version -or
                    $Result[0].Sessions.IsCaptured -or $Result[0].ConnectionOptions.SocketPath -cne $Context.Fixture.SocketPath) {
                    throw 'Inspection example did not preserve daemon identity and version without capturing relationships.'
                }
            } }
        'LibTmux\Get-TmuxSnapshot#1' = @{ ExpectedCount = 1; Isolated = $false; Assert = {
                param($Result, $Context)
                if ($Result[0].Panes.Count -ne 1 -or $Result[0].Panes[0].Id.ToString() -cne $Context.PaneId -or
                    $Result[0].SnapshotMetadata.Depth -ne [LibTmux.SnapshotDepth]::Panes -or
                    ![object]::ReferenceEquals($Result[0], $Result[0].Panes[0].Server) -or
                    ![object]::ReferenceEquals($Result[0].Windows[0], $Result[0].Panes[0].Window)) {
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
        'LibTmux\Set-TmuxLayout#1' = @{ ExpectedCount = 1; Isolated = $true; Prepare = {
                param($Context)
                $server = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath
                $window = $server | LibTmux\Get-TmuxWindow | Select-Object -First 1
                $pane = $window | LibTmux\Get-TmuxPane
                $null = $pane | LibTmux\Split-TmuxPane -Horizontal -Command 'exec /bin/cat'
            }; Assert = {
                param($Result)
                $panes = @($Result[0] | LibTmux\Get-TmuxPane)
                if ($panes.Count -ne 2 -or [Math]::Abs($panes[0].Width - $panes[1].Width) -gt 1) { throw 'Layout help did not tile both panes.' }
            } }
        'LibTmux\Set-TmuxWindowSize#1' = @{ ExpectedCount = 1; Isolated = $true; Prepare = {
                param($Context)
                $window = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath | LibTmux\Get-TmuxWindow | Select-Object -First 1
            }; Assert = {
                param($Result)
                if ($Result[0].Width -ne 120 -or $Result[0].Height -ne 40) { throw 'Window-size help did not resize.' }
            } }
        'LibTmux\Set-TmuxPaneSize#1' = @{ ExpectedCount = 1; Isolated = $true; Prepare = {
                param($Context)
                $pane = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath | LibTmux\Get-TmuxPane | Select-Object -First 1
                $null = $pane | LibTmux\Split-TmuxPane -Horizontal -Command 'exec /bin/cat'
            }; Assert = {
                param($Result)
                if ($Result[0].Width -ne 40) { throw 'Pane-size help did not resize.' }
            } }
        'LibTmux\Get-TmuxClient#1' = @{ ExpectedCount = 1; Isolated = $true; Prepare = {
                param($Context)
                $client = Initialize-HelpClient $Context
                $server = $client.Server
            }; Assert = {
                param($Result, $Context)
                if ($Result[0].Name -cne $Context.Client.Name) { throw 'Client help selected the wrong client.' }
            }; Cleanup = { param($Context) if ($Context.ContainsKey('Control')) { $null = $Context.Control.DisposeAsync().AsTask().GetAwaiter().GetResult() } } }
        'LibTmux\Update-TmuxClient#1' = @{ ExpectedCount = 1; Isolated = $true; Prepare = {
                param($Context)
                $client = Initialize-HelpClient $Context
                $server = $client.Server
            }; Assert = {
                param($Result, $Context)
                if ($Result[0].Name -cne $Context.Client.Name) { throw 'Client help selected the wrong client.' }
            }; Cleanup = { param($Context) if ($Context.ContainsKey('Control')) { $null = $Context.Control.DisposeAsync().AsTask().GetAwaiter().GetResult() } } }
        'LibTmux\Get-TmuxClientAttachment#1' = @{ ExpectedCount = 1; Isolated = $true; Prepare = {
                param($Context)
                $client = Initialize-HelpClient $Context
                $server = $client.Server
            }; Assert = {
                param($Result, $Context)
                if ($Result[0].Session.Id -ne $Context.Client.AttachedSessionId -or !$Result[0].Window -or !$Result[0].Pane) { throw 'Attachment help did not resolve native relations.' }
            }; Cleanup = { param($Context) if ($Context.ContainsKey('Control')) { $null = $Context.Control.DisposeAsync().AsTask().GetAwaiter().GetResult() } } }
        'LibTmux\Get-TmuxOption#1' = @{ ExpectedCount = 1; Isolated = $true; Prepare = {
                param($Context)
                $session = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath | LibTmux\Get-TmuxSession -Name 'fixture'
                $null = Invoke-OwnedTmux $Context.Fixture -Arguments @('set-option', '-g', 'status-keys', 'vi')
            }; Assert = {
                param($Result)
                if ($Result[0].Value.Raw -cne 'vi' -or !$Result[0].Inherited) { throw 'Option help read lost inheritance.' }
            } }
        'LibTmux\Set-TmuxOption#1' = @{ ExpectedCount = 1; Isolated = $true; Prepare = {
                param($Context)
                $session = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath | LibTmux\Get-TmuxSession -Name 'fixture'
            }; Assert = {
                param($Result, $Context)
                $actual = (Invoke-OwnedTmux $Context.Fixture -Arguments @('show-options', '-v', '-t', 'fixture', 'status-keys')).StdOut.TrimEnd("`n")
                if ($Result[0].Raw -cne 'vi' -or $actual -cne 'vi') { throw 'Option help set did not store its readback.' }
            } }
        'LibTmux\Remove-TmuxOption#1' = @{ ExpectedCount = 0; Isolated = $true; Prepare = {
                param($Context)
                $session = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath | LibTmux\Get-TmuxSession -Name 'fixture'
                $null = Invoke-OwnedTmux $Context.Fixture -Arguments @('set-option', '-t', 'fixture', '@scratch', 'temporary')
            }; Assert = {
                param($Result, $Context)
                if ((Invoke-OwnedTmux $Context.Fixture -Arguments @('show-options', '-q', '-t', 'fixture', '@scratch')).StdOut -cne '') { throw 'Option help remove left its entry.' }
            } }
        'LibTmux\Get-TmuxHook#1' = @{ ExpectedCount = 1; Isolated = $true; Prepare = {
                param($Context)
                $session = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath | LibTmux\Get-TmuxSession -Name 'fixture'
                $null = Invoke-OwnedTmux $Context.Fixture -Arguments @('set-hook', '-t', 'fixture', 'alert-bell[7]', 'display-message seven')
            }; Assert = {
                param($Result)
                if ($Result[0].Name -cne 'alert-bell' -or $Result[0].Values[0].Index -ne 7) { throw 'Hook help read lost grouped index.' }
            } }
        'LibTmux\Set-TmuxHook#1' = @{ ExpectedCount = 1; Isolated = $true; Prepare = {
                param($Context)
                $session = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath | LibTmux\Get-TmuxSession -Name 'fixture'
            }; Assert = {
                param($Result, $Context)
                $actual = (Invoke-OwnedTmux $Context.Fixture -Arguments @('show-hooks', '-t', 'fixture', 'alert-bell')).StdOut
                if ($Result[0].Values[0].Index -ne 7 -or !$actual.Contains('alert-bell[7]') -or !$actual.Contains('build finished')) { throw 'Hook help set lost its indexed command.' }
            } }
        'LibTmux\Invoke-TmuxHook#1' = @{ ExpectedCount = 0; Isolated = $true; Prepare = {
                param($Context)
                $session = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath | LibTmux\Get-TmuxSession -Name 'fixture'
                $null = Invoke-OwnedTmux $Context.Fixture -Arguments @('set-hook', '-t', 'fixture', 'alert-bell', 'wait-for -S help-hook-completed')
            }; Assert = {
                param($Result, $Context)
                $server = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath
                if (!($server | LibTmux\Wait-TmuxChannel -Channel 'help-hook-completed' -Timeout 0.5)) { throw 'Hook help invoke did not signal completion.' }
            } }
        'LibTmux\Remove-TmuxHook#1' = @{ ExpectedCount = 0; Isolated = $true; Prepare = {
                param($Context)
                $session = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath | LibTmux\Get-TmuxSession -Name 'fixture'
                foreach ($index in @(7, 19)) {
                    $null = Invoke-OwnedTmux $Context.Fixture -Arguments @('set-hook', '-t', 'fixture', "alert-bell[$index]", "display-message $index")
                }
            }; Assert = {
                param($Result, $Context)
                $actual = (Invoke-OwnedTmux $Context.Fixture -Arguments @('show-hooks', '-t', 'fixture', 'alert-bell')).StdOut
                if ($actual.Contains('alert-bell[7]') -or !$actual.Contains('alert-bell[19]')) { throw 'Hook help remove changed the wrong entries.' }
            } }
        'LibTmux\Get-TmuxEnvironment#1' = @{ ExpectedCount = 1; Isolated = $true; Prepare = {
                param($Context)
                $session = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath | LibTmux\Get-TmuxSession -Name 'fixture'
                $null = Invoke-OwnedTmux $Context.Fixture -Arguments @('set-environment', '-t', 'fixture', 'APP_MODE', 'development')
            }; Assert = {
                param($Result)
                if ($Result[0].Name -cne 'APP_MODE' -or $Result[0].Value -cne 'development' -or $Result[0].IsRemoved) { throw 'Environment help read lost stored value.' }
            } }
        'LibTmux\Set-TmuxEnvironment#1' = @{ ExpectedCount = 1; Isolated = $true; Prepare = {
                param($Context)
                $session = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath | LibTmux\Get-TmuxSession -Name 'fixture'
            }; Assert = {
                param($Result, $Context)
                $actual = (Invoke-OwnedTmux $Context.Fixture -Arguments @('show-environment', '-t', 'fixture', 'APP_MODE')).StdOut.TrimEnd("`n")
                if ($Result[0].Value -cne 'development' -or $actual -cne 'APP_MODE=development') { throw 'Environment help set did not store its readback.' }
            } }
        'LibTmux\Remove-TmuxEnvironment#1' = @{ ExpectedCount = 0; Isolated = $true; Prepare = {
                param($Context)
                $session = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath | LibTmux\Get-TmuxSession -Name 'fixture'
                $null = Invoke-OwnedTmux $Context.Fixture -Arguments @('set-environment', '-g', 'APP_MODE', 'inherited')
            }; Assert = {
                param($Result, $Context)
                $actual = (Invoke-OwnedTmux $Context.Fixture -Arguments @('show-environment', '-t', 'fixture', 'APP_MODE')).StdOut.TrimEnd("`n")
                if ($actual -cne '-APP_MODE') { throw 'Environment help removal did not leave a marker.' }
            } }
        'LibTmux\New-TmuxCommand#1' = @{ ExpectedCount = 1; Isolated = $false; Assert = {
                param($Result)
                if ($Result[0].Name -cne 'display-message' -or [string]::Join('|', $Result[0].Arguments) -cne '-p|hello; tmux') {
                    throw 'Command example lost literal argv.'
                }
            } }
        'LibTmux\Invoke-TmuxChain#1' = @{ ExpectedCount = 1; Isolated = $true; Prepare = {
                param($Context)
                $server = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath
            }; Assert = {
                param($Result)
                if ($Result[0].ExitCode -ne 0 -or [string]::Join('|', $Result[0].StandardOutputLines) -cne 'first|second') {
                    throw 'Chain example lost ordered merged output.'
                }
            } }
        'LibTmux\Connect-TmuxControl#1' = @{ ExpectedCount = 1; Isolated = $true; Prepare = {
                param($Context)
                $server = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath
                $Context.Control = $null
            }; Assert = {
                param($Result, $Context)
                $Context.Control = $Result[0]
                if (!$Result[0].IsRunning -or
                    [string]::Join('|', $Result[0].SendAsync([LibTmux.TmuxCommand]::Create('display-message', [string[]] @('-p', '#{session_name}'))).GetAwaiter().GetResult()) -cne 'fixture') {
                    throw 'Control attachment example selected the wrong session.'
                }
            }; Cleanup = {
                param($Context)
                if ($Context.Control) { $null = $Context.Control.DisposeAsync().AsTask().GetAwaiter().GetResult() }
                if (@(LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath | LibTmux\Get-TmuxClient).Count) {
                    throw 'Control attachment example leaked its client.'
                }
            } }
        'LibTmux\Invoke-TmuxControlCommand#1' = @{ ExpectedCount = 1; Isolated = $true; Prepare = {
                param($Context)
                $server = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath
                $Context.Control = $control = $server | LibTmux\Connect-TmuxControl -Target fixture
            }; Assert = {
                param($Result)
                if ($Result[0] -cne 'fixture') { throw 'Control send example did not print the attached session.' }
            }; Cleanup = {
                param($Context)
                if ($Context.Control) { $null = $Context.Control.DisposeAsync().AsTask().GetAwaiter().GetResult() }
            } }
        'LibTmux\Disconnect-TmuxControl#1' = @{ ExpectedCount = 0; Isolated = $true; Prepare = {
                param($Context)
                $server = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath
                $Context.Control = $control = $server | LibTmux\Connect-TmuxControl -Target fixture
            }; Assert = {
                param($Result, $Context)
                $server = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath
                if ($Context.Control.IsRunning -or @($server | LibTmux\Get-TmuxClient).Count -ne 0 -or
                    @($server | LibTmux\Get-TmuxSession -Name fixture).Count -ne 1) {
                    throw 'Control disconnect example leaked a client or removed a borrowed session.'
                }
            }; Cleanup = {
                param($Context)
                if ($Context.Control) { $null = $Context.Control.DisposeAsync().AsTask().GetAwaiter().GetResult() }
            } }
        'LibTmux\Watch-TmuxEvent#1' = @{ ExpectedCount = 1; Isolated = $true; Prepare = {
                param($Context)
                $server = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath
            }; Assert = {
                param($Result, $Context)
                $server = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath
                if ($Result[0] -isnot [LibTmux.TmuxNotificationEvent] -or @($server | LibTmux\Get-TmuxClient).Count -ne 0 -or
                    @($server | LibTmux\Get-TmuxSession -Name fixture).Count -ne 1) {
                    throw 'Watch example lost its notification, leaked a client or removed the borrowed session.'
                }
            } }
        'LibTmux\Wait-TmuxChannel#1' = @{ ExpectedCount = 1; Isolated = $true; Prepare = {
                param($Context)
                $server = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath
                $null = Invoke-OwnedTmux $Context.Fixture -Arguments @('wait-for', '-S', 'build-finished')
            }; Assert = {
                param($Result)
                if ($Result[0] -isnot [bool] -or !$Result[0]) { throw 'Wait example did not consume its pending signal.' }
            } }
        'LibTmux\Send-TmuxText#1' = @{ ExpectedCount = 0; Isolated = $true; Prepare = {
                param($Context)
                $server = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath
                $session = $server | LibTmux\Get-TmuxSession -Name 'fixture'
                $Context.InputReceiver = New-InputReceiver $Context.Fixture $session 5
                $pane = $Context.InputReceiver.Pane
            }; Assert = {
                param($Result, $Context)
                Assert-Received $Context.Fixture $Context.InputReceiver ([Text.Encoding]::UTF8.GetBytes('Enter'))
            } }
        'LibTmux\Send-TmuxKey#1' = @{ ExpectedCount = 0; Isolated = $true; Prepare = {
                param($Context)
                $server = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath
                $session = $server | LibTmux\Get-TmuxSession -Name 'fixture'
                $Context.InputReceiver = New-InputReceiver $Context.Fixture $session 2
                $pane = $Context.InputReceiver.Pane
            }; Assert = {
                param($Result, $Context)
                Assert-Received $Context.Fixture $Context.InputReceiver ([byte[]] @(1, 13))
            } }
        'LibTmux\Remove-TmuxSession#1' = @{ ExpectedCount = 0; Isolated = $true; Prepare = {
                param($Context)
                $server = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath
                $session = $server | LibTmux\New-TmuxSession -Name 'help-remove-session' -Command 'exec /bin/sh' -Confirm:$false
                $Context.TargetId = $session.Id.ToString()
                $before = Invoke-OwnedTmux $Context.Fixture -Arguments @('display-message', '-p', '-t', $Context.TargetId, '#{session_id}')
                if ($before.StdOut.Trim() -cne $Context.TargetId) { throw 'Session removal example did not prepare its native target.' }
            }; Assert = {
                param($Result, $Context)
                Assert-HelpRemovalOutcome $Context @('list-sessions', '-F', '#{session_id}')
            } }
        'LibTmux\Remove-TmuxWindow#1' = @{ ExpectedCount = 0; Isolated = $true; Prepare = {
                param($Context)
                $server = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath
                $window = $server | LibTmux\Get-TmuxSession -Name 'fixture' |
                    LibTmux\New-TmuxWindow -Name 'help-remove-window' -Command 'exec /bin/sh' -Confirm:$false
                $Context.TargetId = $window.Id.ToString()
                $before = Invoke-OwnedTmux $Context.Fixture -Arguments @('display-message', '-p', '-t', $Context.TargetId, '#{window_id}')
                if ($before.StdOut.Trim() -cne $Context.TargetId) { throw 'Window removal example did not prepare its native target.' }
            }; Assert = {
                param($Result, $Context)
                Assert-HelpRemovalOutcome $Context @('list-windows', '-a', '-F', '#{window_id}')
            } }
        'LibTmux\Remove-TmuxPane#1' = @{ ExpectedCount = 0; Isolated = $true; Prepare = {
                param($Context)
                $server = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath
                $pane = $server | LibTmux\Get-TmuxPane | LibTmux\Split-TmuxPane -Command 'exec /bin/sh' -Confirm:$false
                $Context.TargetId = $pane.Id.ToString()
                $before = Invoke-OwnedTmux $Context.Fixture -Arguments @('display-message', '-p', '-t', $Context.TargetId, '#{pane_id}')
                if ($before.StdOut.Trim() -cne $Context.TargetId) { throw 'Pane removal example did not prepare its native target.' }
            }; Assert = {
                param($Result, $Context)
                Assert-HelpRemovalOutcome $Context @('list-panes', '-a', '-F', '#{pane_id}')
            } }
    }
}

function Assert-HelpRemovalOutcome($Context, [string[]] $ListArguments) {
    $remaining = Invoke-OwnedTmux $Context.Fixture -Arguments $ListArguments
    if ($remaining.StdOut.Split("`n", [StringSplitOptions]::RemoveEmptyEntries) -ccontains $Context.TargetId) {
        throw "Removal example left its native target: $($Context.TargetId)"
    }
    $anchor = Invoke-OwnedTmux $Context.Fixture -Arguments @('display-message', '-p', '-t', 'fixture:0.0',
        '#{session_id}|#{session_name}|#{window_id}|#{window_name}|#{pane_id}|#{pane_pid}')
    if ($anchor.StdOut.Trim() -cne $Context.Anchor) { throw 'Removal example changed the unrelated fixture anchor.' }
}

function Initialize-HelpClient($Context) {
    $server = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath
    $Context.Control = $server.EnterControlModeAsync('fixture').GetAwaiter().GetResult()
    $Context.Client = $server.GetClientsAsync().GetAwaiter().GetResult()[0]
    $null = $Context.Fixture.OwnedProcessIds.Add([int] $Context.Client.RawFormatFields['client_pid'])
    $Context.Client
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
        if ($entry.ContainsKey('Cleanup') -and (!$entry.Isolated -or $entry.Cleanup -isnot [scriptblock])) {
            throw "Invalid isolated help example cleanup: $($example.Id)"
        }
        if ($entry.ContainsKey('Prepare') -and (!$entry.Isolated -or $entry.Prepare -isnot [scriptblock])) {
            throw "Invalid isolated help example preparation: $($example.Id)"
        }
    }
    foreach ($id in $Assertions.Keys) {
        if (!$ids.Contains($id)) { throw "Help example assertion has no packaged example: $id" }
    }
}
