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
        @{ File = 'tmuxp-v1.74.0-environment_vars.yaml'; Hash = 'fd1526dbe34c0b8695818103b25ab950208915ee25775682078fb213d955b4a7' }
    )) {
    $path = Join-Path $corpusFixtures $source.File
    $hash = [Convert]::ToHexString(
        [Security.Cryptography.SHA256]::HashData([IO.File]::ReadAllBytes($path))).ToLowerInvariant()
    Assert-WorkspaceCorpus ($hash -ceq $source.Hash) "$($source.File) changed from the pinned tmuxp fixture"
}
$modifierFailure = $null
try {
    $null = LibTmux.Workspace\Import-TmuxWorkspace -Yaml @'
windows:
  - panes:
      - shell_command:
          - cmd: echo ready
            enter: false
'@ -ErrorAction Stop
} catch { $modifierFailure = $_ }
Assert-WorkspaceCorpus ($null -ne $modifierFailure -and
    $modifierFailure.Exception -is [LibTmux.Workspace.WorkspaceFormatException] -and
    $modifierFailure.Exception.Message.Contains('shell_command[0]') -and
    $modifierFailure.Exception.Message.Contains('enter') -and
    $modifierFailure.Exception.Message.Contains('At line 5, column')) 'unsupported tmuxp command modifier was accepted or lost its location'

# One YAML creation and one JSON append cover the declaration semantics that
# must survive parsing, resolution, planning and real pane startup together.
Invoke-WithOwnedTmux {
    param($fixture)
    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $fixture.TmuxPath
    $created = $null
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
            $sent = @($plan.Actions | Where-Object Kind -eq SendText | ForEach-Object { $_.Request })
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
                Assert-WorkspaceCorpus ($waiter.WaitAsync([TimeSpan]::FromSeconds(1)).GetAwaiter().GetResult()) "$format pane command completion"
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
            $panes.Count -eq 2 -and $panes[0].CurrentPath -ceq $firstDirectory -and
            $panes[1].CurrentPath -ceq $secondDirectory -and
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
    $threeCommands = @($threePlan.Actions | Where-Object Kind -eq SendText | ForEach-Object { $_.Request })
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
        $directoryPanes[0].CurrentPath -ceq '/usr' -and
        $directoryPanes[1].CurrentPath -ceq '/etc') 'upstream first-pane start directory did not reach native panes'

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
            $completed = $panes[$paneIndex] | LibTmux\Invoke-TmuxPaneCommand -Command $command -Timeout 1 -Confirm:$false -ErrorAction Stop
            Assert-WorkspaceCorpus ($completed.ExitStatus -eq 0 -and !$completed.TimedOut) "upstream environment pane $windowIndex/$paneIndex did not finish its probe"
            $observed = [IO.File]::ReadAllText($outputPath)
            Assert-WorkspaceCorpus ($observed -ceq $expectedWindow.Values[$paneIndex]) "upstream environment pane $windowIndex/$paneIndex lost its FOO override"
        }
    }
    Assert-WorkspaceCorpus ([int](Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '#{pid}')).StdOut -eq $fixture.ServerPid) 'corpus application replaced the borrowed daemon'
}
'PASS workspace corpus: local YAML/JSON, unchanged tmuxp windows/directories/environment, and detached daemon'
