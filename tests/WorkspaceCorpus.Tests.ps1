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
            LibTmux.Workspace\Resolve-TmuxWorkspace -BaseDirectory $caseDirectory -Variables @{ PROJECT_ROOT = 'project' } -ErrorAction Stop
        Assert-WorkspaceCorpus ($workspace.DocumentDirectory -ceq $caseDirectory -and
            $workspace.Windows[0].Panes[0].StartDirectory -ceq $firstDirectory -and
            $workspace.Windows[0].Panes[1].StartDirectory -ceq $secondDirectory) "$format file-relative expansion and directory inheritance"

        $policy = if ($format -ceq 'json') { 'Append' } else { 'Error' }
        $plan = $workspace | LibTmux.Workspace\Get-TmuxWorkspacePlan -Server $server -ExistingSession $policy -ErrorAction Stop
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
    Assert-WorkspaceCorpus ([int](Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '#{pid}')).StdOut -eq $fixture.ServerPid) 'corpus application replaced the borrowed daemon'
}
'PASS workspace corpus: YAML creation, multi-window JSON append, inherited commands/environment/paths, options, focus, layouts and detached daemon'
