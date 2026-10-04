param(
    [Parameter(Mandatory)] [string] $ModuleRoot,
    [string] $CorpusFixtureRoot = (Join-Path $PSScriptRoot 'fixtures/workspace')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = (Resolve-Path $ModuleRoot).Path
$corpusFixtures = (Resolve-Path $CorpusFixtureRoot).Path
Import-Module (Join-Path $root 'LibTmux/0.1.0/LibTmux.psd1')
Import-Module (Join-Path $root 'LibTmux.Workspace/0.1.0/LibTmux.Workspace.psd1')
. "$PSScriptRoot/support/OwnedTmux.ps1"

function Assert-WorkspaceCorpus([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "Workspace corpus: $Message" }
}

$upstreamSource = Join-Path $corpusFixtures 'tmuxp-v1.74.0-two_windows.yaml'
$upstreamHash = [Convert]::ToHexString(
    [Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($upstreamSource))).ToLowerInvariant()
Assert-WorkspaceCorpus ($upstreamHash -ceq 'd96733a6709f2bb3c295f6d4abae73ac3f5697009a6da86123c0dba1992282e9') 'upstream tmuxp fixture changed'
$upstream = LibTmux.Workspace\Import-TmuxWorkspace -LiteralPath $upstreamSource -ErrorAction Stop
$upstreamResolved = $upstream.Resolve($corpusFixtures, $null)
Assert-WorkspaceCorpus ($upstreamResolved.SessionName -ceq 'sample_two_windows' -and
    $upstreamResolved.Windows.Count -eq 2 -and
    $upstreamResolved.Windows[0].WindowName -ceq 'first' -and
    $upstreamResolved.Windows[1].WindowName -ceq 'second' -and
    $upstreamResolved.Windows[0].Panes[0].ShellCommands[0] -ceq "echo 'first window'" -and
    $upstreamResolved.Windows[1].Panes[0].ShellCommands[0] -ceq "echo 'second window'") 'tmuxp command objects lost their text or window order'
foreach ($source in @(
        @{ File = 'tmuxp-v1.74.0-three_windows.yaml'; Hash = 'e7c9d625d3d976859839174631db35eacf7b797943465ab15e2b8521f1b86e2e' },
        @{ File = 'tmuxp-v1.74.0-first_pane_start_directory.yaml'; Hash = 'f68399d1cb2a7c55c0a704287d97f02cfb185e4392f0e4702366286fb02cfa2f' },
        @{ File = 'tmuxp-v1.74.0-environment_vars.yaml'; Hash = 'fd1526dbe34c0b8695818103b25ab950208915ee25775682078fb213d955b4a7' },
        @{ File = 'tmuxp-v1.74.0-window_options.yaml'; Hash = '09b7ba17cc1436bd3c2b36c7546db1c05de78c2391eee271cb07426c37d12cb4' },
        @{ File = 'tmuxp-v1.74.0-window_index.yaml'; Hash = '07504a692b8ae31192772e3fcea01906d85b6949555e62bc6191d116b807bdc2' }
    )) {
    $path = Join-Path $corpusFixtures $source.File
    $hash = [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($path))).ToLowerInvariant()
    Assert-WorkspaceCorpus ($hash -ceq $source.Hash) "$($source.File) changed from the pinned tmuxp fixture"
}
$enterDeclarations = @{}
foreach ($source in @(
        @{ File = 'tmuxp-v1.74.0-skip-send.yaml'; Hash = '94f9966e4a8b7540d1fcf8297af3b86c239f6376019cd954174ddc8af4644529' },
        @{ File = 'tmuxp-v1.74.0-skip-send.json'; Hash = '3615f4c75ff43fbed2ed71d4a9e5bdb2bc1688871b3d26634a7fa8f25a3b0d52' },
        @{ File = 'tmuxp-v1.74.0-skip-send-pane-level.yaml'; Hash = 'bbcfafd8a18df84e1d7ba82b317412234c943ef18404e16bd8a671a575a2a96f' },
        @{ File = 'tmuxp-v1.74.0-skip-send-pane-level.json'; Hash = '53b7ef9cf0f96772988c36b807b1e1fc3cd9f82fa13c7c9ce71af670c616d6f8' }
    )) {
    $path = Join-Path $corpusFixtures $source.File
    $hash = [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($path))).ToLowerInvariant()
    Assert-WorkspaceCorpus ($hash -ceq $source.Hash) "$($source.File) changed from tmuxp v1.74.0"
    $enterDeclarations[$source.File] = LibTmux.Workspace\Import-TmuxWorkspace -LiteralPath $path -ErrorAction Stop
}
$invalidEnter = $null
try {
    $null = LibTmux.Workspace\Import-TmuxWorkspace -Yaml @'
windows:
  - panes:
      - shell_command:
          - cmd: echo ready
            enter: maybe
'@ -ErrorAction Stop
} catch { $invalidEnter = $_ }
Assert-WorkspaceCorpus ($null -ne $invalidEnter -and
    $invalidEnter.Exception -is [LibTmux.Workspace.WorkspaceFormatException] -and
    $invalidEnter.Exception.Message.Contains('shell_command[0].enter') -and
    $invalidEnter.Exception.Message.Contains('At line 5, column')) 'invalid command Enter did not retain its source location'

# One YAML creation and one JSON append cover the declaration semantics that
# must survive parsing, resolution, planning and real pane startup together.
Invoke-WithOwnedTmux {
    param($fixture)
    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $fixture.TmuxPath
    $created = $null
    foreach ($format in @('yaml', 'json')) {
        $commandLevel = $enterDeclarations["tmuxp-v1.74.0-skip-send.$format"] |
            LibTmux.Workspace\Get-TmuxWorkspacePlan -Server $server -ErrorAction Stop
        $commands = @($commandLevel.Actions | Where-Object Kind -eq SendText)
        Assert-WorkspaceCorpus ($commands.Count -eq 2 -and
            $commands[0].Request -is [LibTmux.SendKeysRequest] -and
            $commands[0].Request.Text -ceq 'echo "___$((11 + 1))___"' -and
            $commands[0].Request.Enter -and $commands[0].Request.Literal -and
            $commands[1].Request.Text -ceq 'echo "___$((1 + 3))___"' -and
            !$commands[1].Request.Enter -and $commands[1].Request.Literal) "$format command-level Enter plan"
        $preview = $commands | Out-String -Width 200
        Assert-WorkspaceCorpus ($preview.Contains('enter=True') -and
            $preview.Contains('enter=False') -and !$preview.Contains('echo')) `
            "$format preview hid Enter behavior or exposed command text"

        $paneLevel = $enterDeclarations["tmuxp-v1.74.0-skip-send-pane-level.$format"] |
            LibTmux.Workspace\Get-TmuxWorkspacePlan -Server $server -ErrorAction Stop
        $commands = @($paneLevel.Actions | Where-Object Kind -eq SendText)
        Assert-WorkspaceCorpus ($commands.Count -eq 3 -and
            @($commands | Where-Object { $_.Request -isnot [LibTmux.SendKeysRequest] -or
                    $_.Request.Enter -or !$_.Request.Literal }).Count -eq 0) "$format pane-level Enter plan"
    }
    $sticky = LibTmux.Workspace\Import-TmuxWorkspace -Yaml @'
session_name: workspace-enter-sticky
shell_command_before:
  - cmd: root
    enter: false
windows:
  - shell_command_before: [window]
    panes:
      - shell_command_before:
          - cmd: pane
            enter: true
        shell_command:
          - main
          - cmd: hold
            enter: false
          - sticky
          - cmd: resume
            enter: true
          - last
'@ -ErrorAction Stop | LibTmux.Workspace\Resolve-TmuxWorkspace -BaseDirectory $fixture.DirectoryPath -ErrorAction Stop
    $stickyPlan = $sticky | LibTmux.Workspace\Get-TmuxWorkspacePlan -Server $server -ErrorAction Stop
    $stickyRequests = @($stickyPlan.Actions | Where-Object Kind -eq SendText | ForEach-Object Request)
    $expectedText = @('root', 'window', 'pane', 'main', 'hold', 'sticky', 'resume', 'last')
    $expectedEnter = @($false, $false, $true, $true, $false, $false, $true, $true)
    Assert-WorkspaceCorpus ($stickyRequests.Count -eq $expectedText.Count) 'sticky Enter plan changed command count'
    for ($index = 0; $index -lt $expectedText.Count; $index++) {
        Assert-WorkspaceCorpus ($stickyRequests[$index] -is [LibTmux.SendKeysRequest] -and
            $stickyRequests[$index].Text -ceq $expectedText[$index] -and
            $stickyRequests[$index].Enter -eq $expectedEnter[$index] -and
            $stickyRequests[$index].Literal) "sticky Enter plan command $index"
    }
    foreach ($format in @('yaml', 'json')) {
        $caseDirectory = Join-Path $fixture.DirectoryPath $format
        $firstDirectory = Join-Path $caseDirectory 'project/window'
        $secondDirectory = Join-Path $firstDirectory 'pane'
        $null = [IO.Directory]::CreateDirectory($secondDirectory)
        $source = Join-Path $caseDirectory "corpus.$format"
        [IO.File]::Copy((Join-Path $corpusFixtures "corpus.$format"), $source)
        $workspace = Get-Item -LiteralPath $source | LibTmux.Workspace\Import-TmuxWorkspace -ErrorAction Stop |
            LibTmux.Workspace\Resolve-TmuxWorkspace -BaseDirectory $caseDirectory -Variables @{ PROJECT_ROOT = 'project'; OPTION_TAG = 'yaml' } -ErrorAction Stop
        Assert-WorkspaceCorpus ($workspace.DocumentDirectory -ceq $caseDirectory -and
            $workspace.Windows[0].Panes[0].StartDirectory -ceq $firstDirectory -and
            $workspace.Windows[0].Panes[1].StartDirectory -ceq $secondDirectory) "$format file-relative expansion and directory inheritance"
        if ($format -ceq 'yaml') {
            Assert-WorkspaceCorpus ($workspace.Windows[0].Options['@corpus-window'] -ceq 'yaml' -and
                $workspace.ShellCommandsBefore[0] -ceq 'echo session >> order.txt' -and
                $workspace.Windows[0].ShellCommandsBefore[0] -ceq 'echo window >> order.txt' -and
                $workspace.Windows[0].Panes[1].ShellCommandsBefore[0] -ceq 'echo pane >> order.txt' -and
                $workspace.Windows[0].Panes[0].ShellCommands[0] -ceq 'echo command >> order.txt') 'YAML command objects, inherited commands or option value changed during resolution'
        }

        $policy = if ($format -ceq 'json') { 'Append' } else { 'Error' }
        $plan = $workspace | LibTmux.Workspace\Get-TmuxWorkspacePlan -Server $server -ExistingSession $policy -ErrorAction Stop
        if ($format -ceq 'yaml') {
            $sent = @($plan.Actions | Where-Object Kind -eq SendText | ForEach-Object { $_.Request.Text })
            Assert-WorkspaceCorpus ($sent.Count -eq 11 -and
                $sent[0] -ceq 'echo session >> order.txt' -and
                $sent[1] -ceq 'echo window >> order.txt' -and
                $sent[2] -ceq 'echo command >> order.txt' -and
                $sent[5] -ceq 'echo session >> order.txt' -and
                $sent[6] -ceq 'echo window >> order.txt' -and
                $sent[7] -ceq 'echo pane >> order.txt' -and
                $sent[8] -ceq 'echo command >> order.txt') 'YAML command objects lost their pane plan order'
        }
        $waiters = @(@('first', 'second') | ForEach-Object { $server.OpenWaitChannel("corpus-$format-$_") })
        try {
            $result = $plan | LibTmux.Workspace\Invoke-TmuxWorkspace -Confirm:$false -ErrorAction Stop
            Register-OwnedTmuxPane $fixture
            foreach ($waiter in $waiters) {
                Assert-WorkspaceCorpus ($waiter.WaitAsync([TimeSpan]::FromSeconds(10)).GetAwaiter().GetResult()) "$format pane command completion"
            }
        } finally {
            foreach ($waiter in $waiters) { $null = $waiter.DisposeAsync().AsTask().GetAwaiter().GetResult() }
        }
        $firstOrder = [string]::Join(',', [IO.File]::ReadAllLines((Join-Path $firstDirectory 'order.txt')))
        $secondOrder = [string]::Join(',', [IO.File]::ReadAllLines((Join-Path $secondDirectory 'order.txt')))
        $firstEnvironment = [IO.File]::ReadAllText((Join-Path $firstDirectory 'environment.txt')).Trim()
        $secondEnvironment = [IO.File]::ReadAllText((Join-Path $secondDirectory 'environment.txt')).Trim()
        Assert-WorkspaceCorpus ($firstOrder -ceq 'session,window,command' -and
            $secondOrder -ceq 'session,window,pane,command' -and
            $firstEnvironment -ceq "${format}-root|${format}-window||window" -and
            $secondEnvironment -ceq "${format}-root|${format}-window|${format}-pane|pane") "$format inherited command order and scoped environment"

        $window = $result.Windows[0]
        $panes = @($window | LibTmux\Get-TmuxPane)
        Assert-WorkspaceCorpus ($result -is [LibTmux.Workspace.WorkspaceResult] -and
            $result.Session.Name -ceq 'corpus' -and
            $panes.Count -eq 2 -and $panes[0].CurrentPath -ceq (Resolve-PhysicalDirectory $firstDirectory) -and
            $panes[1].CurrentPath -ceq (Resolve-PhysicalDirectory $secondDirectory) -and
            ($window | LibTmux\Get-TmuxOption -Name '@corpus-window').Value.Raw -ceq $format -and
            ($panes[1] | LibTmux\Get-TmuxOption -Name '@corpus-pane').Value.Raw -ceq $format -and
            (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', $panes[1].Id.ToString(), '#{pane_active}')).StdOut.Trim() -ceq '1') "$format native graph, options, focus and directories"
        if ($format -ceq 'yaml') {
            Assert-WorkspaceCorpus ($result.Windows.Count -eq 1 -and
                [Math]::Abs($panes[0].Width - $panes[1].Width) -le 1 -and
                $panes[0].Height -eq $panes[1].Height) 'YAML horizontal layout'
            $created = $result
        } else {
            Assert-WorkspaceCorpus ([Math]::Abs($panes[0].Height - $panes[1].Height) -le 1 -and
                $panes[0].Width -eq $panes[1].Width) 'JSON vertical layout'
            $windows = @($result.Session | LibTmux\Get-TmuxWindow)
            Assert-WorkspaceCorpus ($result.Windows.Count -eq 2 -and
                $result.Windows[0].Name -ceq 'json-console' -and
                $result.Windows[1].Name -ceq 'json-observer' -and
                $result.Windows[0].Id -ne $result.Windows[1].Id -and
                $result.Session.ActiveWindow.Value.Id -eq $result.Windows[0].Id) 'JSON append did not create two distinct windows and focus the first after creating the second'
            Assert-WorkspaceCorpus ($result.Session.Id -eq $created.Session.Id -and
                $windows.Count -eq 3 -and @($windows | Where-Object Id -EQ $created.Windows[0].Id).Count -eq 1 -and
                ($result.Session | LibTmux\Get-TmuxOption -Name '@corpus-session').Value.Raw -ceq 'yaml-original' -and
                (Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '-t', $result.Session.Id.ToString(), '#{window_id}')).StdOut.Trim() -ceq $window.Id.ToString()) 'JSON append did not preserve existing window/options or select its focused window'
        }
        Assert-WorkspaceCorpus ((Invoke-OwnedTmux $fixture -Arguments @('list-clients', '-F', '#{client_pid}')).StdOut.Trim().Length -eq 0) "$format application attached a terminal"
    }

    $three = LibTmux.Workspace\Import-TmuxWorkspace -LiteralPath (Join-Path $corpusFixtures 'tmuxp-v1.74.0-three_windows.yaml') -ErrorAction Stop
    $three = $three.Resolve($fixture.DirectoryPath, $null)
    $threePlan = $three | LibTmux.Workspace\Get-TmuxWorkspacePlan -Server $server -ErrorAction Stop
    $threeCommands = @($threePlan.Actions | Where-Object Kind -eq SendText | ForEach-Object { $_.Request.Text })
    Assert-WorkspaceCorpus ($threeCommands.Count -eq 3 -and
        $threeCommands[0] -ceq "echo 'first window'" -and
        $threeCommands[1] -ceq "echo 'second window'" -and
        $threeCommands[2] -ceq "echo 'third window'") 'upstream three-window plan lost command text or order'
    $threeResult = $threePlan | LibTmux.Workspace\Invoke-TmuxWorkspace -Confirm:$false -ErrorAction Stop
    Register-OwnedTmuxPane $fixture
    $threeWindows = @($threeResult.Session | LibTmux\Get-TmuxWindow)
    Assert-WorkspaceCorpus ($threeResult.Session.Name -ceq 'sample_three_windows' -and
        $threeWindows.Count -eq 3 -and
        [string]::Join(',', @($threeWindows | ForEach-Object Name)) -ceq 'first,second,third') 'upstream three-window native graph or order changed'
    foreach ($index in 0..2) {
        $panes = @($threeWindows[$index] | LibTmux\Get-TmuxPane)
        Assert-WorkspaceCorpus ($panes.Count -eq 1) "upstream window $index did not have one native pane"
    }

    $directories = LibTmux.Workspace\Import-TmuxWorkspace -LiteralPath (Join-Path $corpusFixtures 'tmuxp-v1.74.0-first_pane_start_directory.yaml') -ErrorAction Stop
    $directories = $directories.Resolve($fixture.DirectoryPath, $null)
    $directoryPlan = $directories | LibTmux.Workspace\Get-TmuxWorkspacePlan -Server $server -ErrorAction Stop
    $createWindow = @($directoryPlan.Actions | Where-Object Kind -eq CreateWindow)
    $splitPane = @($directoryPlan.Actions | Where-Object Kind -eq SplitPane)
    Assert-WorkspaceCorpus ($createWindow.Count -eq 1 -and $splitPane.Count -eq 1 -and
        $createWindow[0].Request.StartDirectory -ceq '/usr' -and
        $splitPane[0].Request.StartDirectory -ceq '/etc') 'upstream first-pane directories were not planned for their own panes'
    $directoryResult = $directoryPlan | LibTmux.Workspace\Invoke-TmuxWorkspace -Confirm:$false -ErrorAction Stop
    Register-OwnedTmuxPane $fixture
    $directoryWindows = @($directoryResult.Session | LibTmux\Get-TmuxWindow)
    Assert-WorkspaceCorpus ($directoryResult.Session.Name -ceq 'sample workspace' -and
        $directoryWindows.Count -eq 1) 'upstream first-pane directory fixture did not create one window'
    $directoryPanes = @($directoryWindows[0] | LibTmux\Get-TmuxPane)
    Assert-WorkspaceCorpus ($directoryPanes.Count -eq 2 -and
        $directoryPanes[0].CurrentPath -ceq (Resolve-PhysicalDirectory '/usr') -and
        $directoryPanes[1].CurrentPath -ceq (Resolve-PhysicalDirectory '/etc')) 'upstream first-pane start directory did not reach native panes'
    $directoryResult.Session | LibTmux\Remove-TmuxSession -Confirm:$false -ErrorAction Stop

    $environment = LibTmux.Workspace\Import-TmuxWorkspace -LiteralPath (Join-Path $corpusFixtures 'tmuxp-v1.74.0-environment_vars.yaml') -ErrorAction Stop
    $environment = $environment | LibTmux.Workspace\Resolve-TmuxWorkspace -BaseDirectory $fixture.DirectoryPath `
        -Variables @{ HOME = $fixture.DirectoryPath } -ErrorAction Stop
    $environmentPlan = $environment | LibTmux.Workspace\Get-TmuxWorkspacePlan -Server $server -ErrorAction Stop
    $createSession = @($environmentPlan.Actions | Where-Object Kind -eq CreateSession)
    Assert-WorkspaceCorpus ($createSession.Count -eq 1 -and
        $createSession[0].Request.Environment['FOO'] -ceq 'SESSION' -and
        $createSession[0].Request.Environment['PATH'] -ceq '/tmp') 'upstream session environment was not planned'
    $environmentResult = $environmentPlan | LibTmux.Workspace\Invoke-TmuxWorkspace -Confirm:$false -ErrorAction Stop
    Register-OwnedTmuxPane $fixture
    $sessionPath = (Invoke-OwnedTmux $fixture -Arguments @('show-environment', '-t',
            $environmentResult.Session.Id.ToString(), 'PATH')).StdOut.Trim()
    Assert-WorkspaceCorpus ($sessionPath -ceq 'PATH=/tmp') 'upstream session PATH did not reach native tmux environment'
    $environmentWindows = @($environmentResult.Session | LibTmux\Get-TmuxWindow)
    $expectedEnvironment = @(
        @{ Name = 'no_overrides'; Values = @('SESSION') },
        @{ Name = 'window_overrides'; Values = @('WINDOW') },
        @{ Name = 'pane_overrides'; Values = @('PANE') },
        @{ Name = 'both_overrides'; Values = @('WINDOW', 'PANE') },
        @{ Name = 'both_overrides_on_first_pane'; Values = @('PANE') }
    )
    Assert-WorkspaceCorpus ($environmentResult.Session.Name -ceq 'test env vars' -and
        $environmentWindows.Count -eq $expectedEnvironment.Count) 'upstream environment fixture did not create five windows'
    for ($windowIndex = 0; $windowIndex -lt $expectedEnvironment.Count; $windowIndex++) {
        $window = $environmentWindows[$windowIndex]
        $expectedWindow = $expectedEnvironment[$windowIndex]
        $panes = @($window | LibTmux\Get-TmuxPane)
        Assert-WorkspaceCorpus ($window.Name -ceq $expectedWindow.Name -and
            $panes.Count -eq $expectedWindow.Values.Count) "upstream environment window $windowIndex changed its native graph"
        for ($paneIndex = 0; $paneIndex -lt $panes.Count; $paneIndex++) {
            $outputPath = Join-Path $fixture.DirectoryPath "environment-$windowIndex-$paneIndex.txt"
            $quotedOutput = "'" + $outputPath.Replace("'", "'\''") + "'"
            $command = 'printf "%s" "$FOO" > ' + $quotedOutput
            $completed = $panes[$paneIndex] | LibTmux\Invoke-TmuxPaneCommand -Command $command -Timeout 10 -Confirm:$false -ErrorAction Stop
            Assert-WorkspaceCorpus ($completed.ExitStatus -eq 0 -and !$completed.TimedOut) "upstream environment pane $windowIndex/$paneIndex did not finish its probe"
            $observed = [IO.File]::ReadAllText($outputPath)
            Assert-WorkspaceCorpus ($observed -ceq $expectedWindow.Values[$paneIndex]) "upstream environment pane $windowIndex/$paneIndex lost its FOO override"
        }
    }
    $windowOptions = LibTmux.Workspace\Import-TmuxWorkspace -LiteralPath (Join-Path $corpusFixtures 'tmuxp-v1.74.0-window_options.yaml') -ErrorAction Stop |
        LibTmux.Workspace\Resolve-TmuxWorkspace -BaseDirectory $fixture.DirectoryPath `
            -Variables @{ HOME = $fixture.DirectoryPath } -ErrorAction Stop
    $windowPlan = $windowOptions | LibTmux.Workspace\Get-TmuxWorkspacePlan -Server $server -ErrorAction Stop
    $layoutAction = @($windowPlan.Actions | Where-Object Kind -eq SelectLayout)
    $optionAction = @($windowPlan.Actions | Where-Object { $_.Kind -eq 'SetOption' -and $_.Request.Name -eq 'main-pane-height' })
    Assert-WorkspaceCorpus ($layoutAction.Count -eq 1 -and $optionAction.Count -eq 1 -and
        $layoutAction[0].Request.Layout -ceq 'main-horizontal' -and
        $optionAction[0].Request.Value -ceq '5') 'upstream window layout or standard option was not planned'
    $windowResult = $windowPlan | LibTmux.Workspace\Invoke-TmuxWorkspace -Confirm:$false -ErrorAction Stop
    Register-OwnedTmuxPane $fixture
    $nativeWindows = @($windowResult.Session | LibTmux\Get-TmuxWindow)
    Assert-WorkspaceCorpus ($windowResult.Session.Name -ceq 'test window options' -and
        $nativeWindows.Count -eq 1 -and $nativeWindows[0].Name -ceq 'editor') 'upstream option fixture did not create its named window'
    $nativePanes = @($nativeWindows[0] | LibTmux\Get-TmuxPane)
    $mainPaneHeight = $nativeWindows[0] | LibTmux\Get-TmuxOption -Name 'main-pane-height' -ErrorAction Stop
    Assert-WorkspaceCorpus ($nativePanes.Count -eq 3 -and
        @($nativePanes | Where-Object CurrentPath -CNE (Resolve-PhysicalDirectory $fixture.DirectoryPath)).Count -eq 0 -and
        $mainPaneHeight.Value.Raw -ceq '5' -and !$mainPaneHeight.Inherited) 'upstream window option, pane graph or inherited HOME was not applied'
    $indexed = LibTmux.Workspace\Import-TmuxWorkspace -LiteralPath (Join-Path $corpusFixtures 'tmuxp-v1.74.0-window_index.yaml') -ErrorAction Stop
    $indexed = $indexed.Resolve($fixture.DirectoryPath, $null)
    $indexPlan = $indexed | LibTmux.Workspace\Get-TmuxWorkspacePlan -Server $server -ErrorAction Stop
    $indexCreates = @($indexPlan.Actions | Where-Object Kind -eq CreateWindow)
    Assert-WorkspaceCorpus ($indexCreates.Count -eq 3 -and
        $null -eq $indexCreates[0].Request.Index -and
        $indexCreates[1].Request.Index -ceq '5' -and
        $null -eq $indexCreates[2].Request.Index) 'upstream explicit window index was not planned in declaration order'
    $indexResult = $indexPlan | LibTmux.Workspace\Invoke-TmuxWorkspace -Confirm:$false -ErrorAction Stop
    Register-OwnedTmuxPane $fixture
    $declaredOrder = [string]::Join(',', @($indexResult.Windows | ForEach-Object { "$($_.Name):$($_.Index)" }))
    $nativeIndexWindows = @($indexResult.Session | LibTmux\Get-TmuxWindow)
    $nativeOrder = [string]::Join(',', @($nativeIndexWindows | ForEach-Object { "$($_.Name):$($_.Index)" }))
    Assert-WorkspaceCorpus ($indexResult.Session.Name -ceq 'sample workspace' -and
        $declaredOrder -ceq 'zero:0,five:5,one:1' -and
        $nativeOrder -ceq 'zero:0,one:1,five:5') 'upstream window indexes did not reach native tmux placements'
    Assert-WorkspaceCorpus ([int](Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '#{pid}')).StdOut -eq $fixture.ServerPid) 'corpus application replaced the borrowed daemon'

    $marker = 'ENTER_HELD_' + [Guid]::NewGuid().ToString('N')
    $channel = 'workspace-enter-' + [Guid]::NewGuid().ToString('N')
    $received = Join-Path $fixture.DirectoryPath 'enter-received'
    $quotedFile = "'" + $received.Replace("'", "'\''") + "'"
    $quotedTmux = "'" + $fixture.TmuxPath.Replace("'", "'\''") + "'"
    $quotedSocket = "'" + $fixture.SocketPath.Replace("'", "'\''") + "'"
    $command = "printf '%s' '$marker' > $quotedFile; $quotedTmux -S $quotedSocket wait-for -S $channel"
    $liveDocument = Microsoft.PowerShell.Utility\ConvertTo-Json -InputObject @{
        session_name = 'workspace-enter-live'
        windows = @(@{ panes = @(@{ shell_command = @(@{ cmd = $command; enter = $false }) }) })
    } -Depth 8 -Compress
    $live = LibTmux.Workspace\Import-TmuxWorkspace -Yaml $liveDocument -ErrorAction Stop
    $livePlan = $live | LibTmux.Workspace\Get-TmuxWorkspacePlan -Server $server -ErrorAction Stop
    $pending = @($livePlan.Actions | Where-Object Kind -eq SendText)
    Assert-WorkspaceCorpus ($pending.Count -eq 1 -and
        $pending[0].Request -is [LibTmux.SendKeysRequest] -and
        $pending[0].Request.Text -ceq $command -and
        !$pending[0].Request.Enter -and $pending[0].Request.Literal) 'live Enter plan was not an inspectable literal send without Enter'
    $waiter = $server.OpenWaitChannel($channel)
    $liveSession = $null
    try {
        $liveResult = $livePlan | LibTmux.Workspace\Invoke-TmuxWorkspace -Confirm:$false -ErrorAction Stop
        $liveSession = $liveResult.Session
        Register-OwnedTmuxPane $fixture
        $livePane = @($liveResult.Windows[0] | LibTmux\Get-TmuxPane)[0]
        $pendingText = (Invoke-OwnedTmux $fixture -Arguments @('capture-pane', '-p', '-J', '-t', $livePane.Id.ToString())).StdOut
        Assert-WorkspaceCorpus ($pendingText.Contains($marker) -and
            ![IO.File]::Exists($received)) 'Enter=false executed a command instead of leaving literal text pending'
        $null = $livePane.EnterAsync().GetAwaiter().GetResult()
        Assert-WorkspaceCorpus ($waiter.WaitAsync([TimeSpan]::FromSeconds(1)).GetAwaiter().GetResult() -and
            [IO.File]::ReadAllText($received) -ceq $marker) 'explicit Enter did not execute the pending command'
    } finally {
        $null = $waiter.DisposeAsync().AsTask().GetAwaiter().GetResult()
        if ($liveSession) { $liveSession | LibTmux\Remove-TmuxSession -Confirm:$false -ErrorAction Stop }
    }
    Assert-WorkspaceCorpus ((Invoke-OwnedTmux $fixture -Arguments @('has-session', '-t', 'fixture')).ExitCode -eq 0 -and
        [int](Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '#{pid}')).StdOut -eq $fixture.ServerPid) 'Enter test removed or replaced its borrowed fixture daemon'
}
'PASS workspace corpus: local YAML/JSON, pinned tmuxp declarations, literal pending input and explicit Enter, and detached daemon'
