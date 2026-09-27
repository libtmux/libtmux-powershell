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

    $prepareWorkspacePlan = {
        param($Context)
        $server = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath
        $workspace = LibTmux.Workspace\Import-TmuxWorkspace -Yaml '{session_name: workspace-help, options: {default-command: "exec /bin/cat"}, windows: [{window_name: editor}]}'
        $Plan = $workspace | LibTmux.Workspace\Get-TmuxWorkspacePlan -Server $server
        $Context.Plan = $Plan
    }

    # Each packaged example needs its own outcome assertion, including examples with no output.
    @{
        'LibTmux\Enter-TmuxSession#1' = @{ ExpectedCount = 0; Isolated = $true; Prepare = {
                param($Context)
                $server = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath
                $session = $server | LibTmux\Get-TmuxSession -Name 'fixture'
                $Context.Session = $session
            }; Assert = {
                param($Result, $Context)
                $session = $Context.Session
                if ($Result.Count -ne 0 -or
                    $session.Server.GetSessionAsync($session.Id).GetAwaiter().GetResult().Id -ne $session.Id) {
                    throw 'Attachment preview returned a result or changed the selected session.'
                }
            } }
        'LibTmux\Enter-TmuxSession#2' = @{ ExpectedCount = 1; Isolated = $true; TerminalMode = 'ReadOnly'; Assert = {
                param($Result, $Context)
                if ($Result.Count -ne 1 -or $Result[0] -isnot [LibTmux.Session] -or
                    $Result[0].Id -ne $Context.Session.Id -or
                    $Result[0].Server.ConnectionOptions.SocketPath -cne $Context.Session.Server.ConnectionOptions.SocketPath -or
                    [object]::ReferenceEquals($Result[0], $Context.Session)) {
                    throw 'Attachment example did not return one refreshed session from its explicit endpoint.'
                }
            } }
        'LibTmux.Workspace\ConvertTo-TmuxWorkspace#1' = @{ ExpectedCount = 1; Isolated = $true; Prepare = {
                param($Context)
                $server = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath
                $capturedSession = ($server | LibTmux\Get-TmuxSnapshot -Depth Panes).Sessions[0]
                $Context.CapturedSession = $capturedSession
            }; Assert = {
                param($Result, $Context)
                $workspace = $Result[0]
                $captured = $Context.CapturedSession
                if ($workspace -isnot [LibTmux.Workspace.WorkspaceFile] -or
                    $workspace.SessionName -cne $captured.Name -or $null -ne $workspace.DocumentDirectory -or
                    $workspace.Windows.Count -ne $captured.Windows.Count -or
                    $workspace.Windows[0].Panes.Count -ne $captured.Windows[0].Panes.Count -or
                    @($workspace.Windows | ForEach-Object { $_.Panes } | ForEach-Object { $_.ShellCommands }).Count -ne 0) {
                    throw 'Snapshot conversion example lost captured structure or invented startup commands.'
                }
            } }
        'LibTmux.Workspace\Get-TmuxWorkspace#1' = @{ ExpectedCount = 1; Isolated = $true; Prepare = {
                param($Context)
                $WorkspacePath = Join-Path $Context.Fixture.DirectoryPath '[team].yaml'
                [IO.File]::WriteAllText($WorkspacePath, 'session_name: discovered')
                $Context.WorkspacePath = $WorkspacePath
            }; Assert = {
                param($Result, $Context)
                if ($Result[0] -isnot [IO.FileInfo] -or $Result[0].FullName -cne $Context.WorkspacePath -or
                    ($Result[0] | LibTmux.Workspace\Import-TmuxWorkspace).SessionName -cne 'discovered') {
                    throw 'Workspace discovery example did not return its literal native file.'
                }
            } }
        'LibTmux.Workspace\Resolve-TmuxWorkspace#1' = @{ ExpectedCount = 1; Isolated = $false; Assert = {
                param($Result)
                $expectedBase = (Get-Location).Path
                if ($Result[0] -isnot [LibTmux.Workspace.WorkspaceFile] -or
                    $Result[0].DocumentDirectory -cne $expectedBase -or
                    $Result[0].Windows[0].Panes[0].StartDirectory -cne (Join-Path $expectedBase 'src')) {
                    throw 'Workspace resolution example lost the explicit base or inherited expansion.'
                }
            } }
        'LibTmux.Workspace\Get-TmuxWorkspacePlan#1' = @{ ExpectedCount = 1; Isolated = $false; Assert = {
                param($Result, $Context)
                $plan = $Result[0]
                if ($plan -isnot [LibTmux.Workspace.WorkspacePlan] -or $plan.SessionName -cne 'development' -or
                    $plan.Endpoint.ConnectionOptions.SocketPath -cne $Context.Fixture.SocketPath -or
                    @($plan.Actions | Where-Object Kind -EQ CreateWindow).Count -ne 1 -or
                    @($plan.Endpoint | LibTmux\Get-TmuxSession -Name development).Count -ne 0) {
                    throw 'Workspace plan example lost its native actions or created its session during planning.'
                }
            } }
        'LibTmux.Workspace\Invoke-TmuxWorkspace#1' = @{ ExpectedCount = 0; Isolated = $true; Prepare = $prepareWorkspacePlan; Assert = {
                param($Result, $Context)
                if (@($Context.Plan.Endpoint | LibTmux\Get-TmuxSession -Name workspace-help).Count -ne 0) {
                    throw 'Workspace preview example created the planned session.'
                }
            } }
        'LibTmux.Workspace\Invoke-TmuxWorkspace#2' = @{ ExpectedCount = 1; Isolated = $true; Prepare = $prepareWorkspacePlan; Assert = {
                param($Result, $Context)
                $applied = $Result[0]
                if ($applied -isnot [LibTmux.Workspace.WorkspaceResult] -or
                    $applied.Session.Name -cne 'workspace-help' -or $applied.Windows.Count -ne 1 -or
                    $applied.Windows[0].Name -cne 'editor' -or $applied.Windows[0].Panes.Count -ne 1 -or
                    $applied.Journal.Count -eq 0 -or
                    ![object]::ReferenceEquals($applied.Journal[0].Action, $Context.Plan.Actions[0])) {
                    throw 'Workspace apply example did not execute its exact plan into the expected captured session.'
                }
            } }
        'LibTmux.Workspace\Test-TmuxWorkspace#1' = @{ ExpectedCount = 1; Isolated = $false; Assert = {
                param($Result)
                if ($Result[0] -isnot [bool] -or !$Result[0]) {
                    throw 'Workspace validation example did not accept its complete declaration.'
                }
            } }
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
        'LibTmux.Workspace\ConvertTo-TmuxWorkspaceYaml#1' = @{ ExpectedCount = 1; Isolated = $false; Assert = {
                param($Result)
                $workspace = LibTmux.Workspace\Import-TmuxWorkspace -Yaml $Result[0]
                if ($Result[0] -isnot [string] -or $workspace.SessionName -cne 'development' -or
                    $workspace.Windows[0].Panes.Count -ne 2 -or
                    $workspace.Windows[0].Panes[0].ShellCommands[0] -cne 'nvim' -or
                    $workspace.Windows[0].Panes[1].ShellCommands[0] -cne '') {
                    throw 'YAML conversion example lost the declared workspace or pane order.'
                }
            } }
        'LibTmux.Workspace\ConvertTo-TmuxWorkspaceJson#1' = @{ ExpectedCount = 1; Isolated = $false; Assert = {
                param($Result)
                $workspace = LibTmux.Workspace\Import-TmuxWorkspace -Yaml $Result[0]
                if ($Result[0] -isnot [string] -or $workspace.SessionName -cne 'development' -or
                    $workspace.Windows[0].Panes.Count -ne 2 -or
                    $workspace.Windows[0].Panes[0].ShellCommands[0] -cne 'nvim' -or
                    $workspace.Windows[0].Panes[1].ShellCommands[0] -cne '') {
                    throw 'JSON conversion example lost the declared workspace or pane order.'
                }
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
        'LibTmux\New-TmuxWindowLink#1' = @{ ExpectedCount = 0; Isolated = $true; Prepare = {
                param($Context)
                $server = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath
                $guest = $server | LibTmux\New-TmuxSession -Name 'help-link-guest' -Command 'exec /bin/sh' -Confirm:$false
                $source = $server | LibTmux\Get-TmuxSession -Name fixture
                $window = $source | LibTmux\New-TmuxWindow -Name 'help-link-source' -Index 4 -Command 'exec /bin/sh' -Confirm:$false
                $Context.Guest = $guest
                $Context.Source = $source
                $Context.WindowId = $window.Id
            }; Assert = {
                param($Result, $Context)
                $linked = @($Context.Guest | LibTmux\Get-TmuxWindow | Where-Object { $_.Id -eq $Context.WindowId -and $_.Index -eq 5 })
                $source = @($Context.Source | LibTmux\Get-TmuxWindow | Where-Object { $_.Id -eq $Context.WindowId -and $_.Index -eq 4 })
                if ($Result.Count -ne 0 -or $linked.Count -ne 1 -or $source.Count -ne 1) {
                    throw 'Window-link help did not retain source and create destination placement.'
                }
            } }
        'LibTmux\Move-TmuxWindow#1' = @{ ExpectedCount = 1; Isolated = $true; Prepare = {
                param($Context)
                $server = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath
                $source = $server | LibTmux\Get-TmuxSession -Name fixture
                $window = $source | LibTmux\New-TmuxWindow -Name 'help-move-source' -Index 4 -Command 'exec /bin/sh' -Confirm:$false
                $Context.Source = $source
                $Context.Original = $window
            }; Assert = {
                param($Result, $Context)
                $moved = @($Context.Source | LibTmux\Get-TmuxWindow | Where-Object { $_.Id -eq $Context.Original.Id -and $_.Index -eq 5 })
                if ($Result.Count -ne 1 -or $Result[0] -isnot [LibTmux.Window] -or
                    $Result[0].Index -ne 5 -or $Context.Original.Index -ne 4 -or $moved.Count -ne 1) {
                    throw 'Window-move help did not return a replacement at the destination index.'
                }
            } }
        'LibTmux\Remove-TmuxWindowLink#1' = @{ ExpectedCount = 0; Isolated = $true; Prepare = {
                param($Context)
                $server = LibTmux\New-TmuxServer -SocketPath $Context.Fixture.SocketPath -TmuxBinaryPath $Context.Fixture.TmuxPath
                $source = $server | LibTmux\New-TmuxSession -Name 'help-unlink-source' -Command 'exec /bin/sh' -Confirm:$false
                $guest = $server | LibTmux\Get-TmuxSession -Name fixture
                $sourceWindow = $source | LibTmux\Get-TmuxWindow
                $sourceWindow | LibTmux\New-TmuxWindowLink -Session $guest -Index 5 -NoSelect -Confirm:$false
                $window = $guest | LibTmux\Get-TmuxWindow | Where-Object { $_.Id -eq $sourceWindow.Id -and $_.Index -eq 5 }
                $Context.Source = $source
                $Context.Guest = $guest
                $Context.WindowId = $sourceWindow.Id
            }; Assert = {
                param($Result, $Context)
                $guest = @($Context.Guest | LibTmux\Get-TmuxWindow | Where-Object Id -EQ $Context.WindowId)
                $source = @($Context.Source | LibTmux\Get-TmuxWindow | Where-Object Id -EQ $Context.WindowId)
                if ($Result.Count -ne 0 -or $guest.Count -ne 0 -or $source.Count -ne 1) {
                    throw 'Window-unlink help removed more than the selected placement.'
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
        if ($entry.ContainsKey('TerminalMode') -and (!$entry.Isolated -or
            $entry.TerminalMode -cne 'ReadOnly' -or $example.Id -cne 'LibTmux\Enter-TmuxSession#2')) {
            throw "Invalid terminal help example owner: $($example.Id)"
        }
    }
    foreach ($id in $Assertions.Keys) {
        if (!$ids.Contains($id)) { throw "Help example assertion has no packaged example: $id" }
    }
}

function Get-HelpExampleCode($Example, [string] $Name) {
    $code = [string] $Example.code
    if ([string]::IsNullOrWhiteSpace($code)) {
        # PlatyPS 1.0.3 leaves dev:code empty and retains the fenced introduction.
        $text = $Example.introduction.Text -join "`n"
        $blocks = [regex]::Matches($text, '(?ms)^```powershell[ \t]*\r?\n(?<code>.*?)^```[ \t]*\r?$')
        if ($blocks.Count -ne 1) {
            throw "$Name must have exactly one executable PowerShell block per example."
        }
        $code = $blocks[0].Groups['code'].Value
    }
    if ([string]::IsNullOrWhiteSpace($code)) { throw "$Name has an example without executable code." }
    $parseErrors = $null
    $null = [Management.Automation.Language.Parser]::ParseInput($code, [ref] $null, [ref] $parseErrors)
    if ($parseErrors.Count) { throw "$Name has invalid example syntax: $($parseErrors.Message -join '; ')." }
    $code
}
