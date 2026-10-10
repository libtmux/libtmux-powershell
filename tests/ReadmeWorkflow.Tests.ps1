param([Parameter(Mandatory)] [string] $ModuleRoot, [switch] $Child)

# Outer integration: run unchanged README blocks in an isolated child environment.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot
$readme = [IO.File]::ReadAllText("$root/README.md")
$moduleRootPath = (Resolve-Path -LiteralPath $ModuleRoot).Path

function Get-ReadmeBlock([string] $Id) {
    $pattern = '(?ms)^<!-- example: ' + [regex]::Escape($Id) + ' -->\r?\n```powershell\r?\n(?<code>.*?)^```[ \t]*$'
    $blocksFound = [regex]::Matches($readme, $pattern)
    if ($blocksFound.Count -ne 1) { throw "README example is missing or repeated: $Id" }
    [scriptblock]::Create($blocksFound[0].Groups['code'].Value)
}

function Assert-Readme([bool] $Condition, [string] $Message) {
    if (!$Condition) { throw "README workflow: $Message" }
}

if (!$Child) {
    . "$PSScriptRoot/support/OwnedTmux.ps1"
    $fixture = New-OwnedTmuxFixture
    $process = $null
    $bodyError = $null
    try {
        $start = [Diagnostics.ProcessStartInfo]::new([Environment]::ProcessPath)
        $start.UseShellExecute = $false
        $start.WorkingDirectory = $root
        $start.Environment['LIBTMUX_SOCKET_PATH'] = $fixture.SocketPath
        $start.Environment['LIBTMUX_SOCKET_NAME'] = '../ignored'
        $start.Environment['TMUX'] = 'ignored malformed context'
        $start.Environment['TMUX_PANE'] = '%987654'
        $start.Environment['LIBTMUX_README_OWNED_SOCKET'] = $fixture.SocketPath
        foreach ($argument in @('-NoLogo', '-NoProfile', '-File', $PSCommandPath,
            '-ModuleRoot', $moduleRootPath, '-Child')) { $start.ArgumentList.Add($argument) }
        $process = [Diagnostics.Process]::Start($start)
        if (!$process.WaitForExit(20000)) { throw 'README child exceeded its deadline.' }
        if ($process.ExitCode) { throw "README child failed with exit $($process.ExitCode)." }
        $sessions = Invoke-OwnedTmux $fixture -Arguments @('-N', 'list-sessions', '-F', '#{session_name}')
        Assert-Readme ($sessions.StdOut.Trim() -ceq 'fixture') 'README left an example session alive'
    } catch {
        $bodyError = $_
        throw
    } finally {
        try {
            if ($process -and !$process.HasExited) {
                $process.Kill($true)
                if (!$process.WaitForExit(1000)) { throw 'README child survived termination.' }
            }
            Remove-OwnedTmuxFixture $fixture
            Assert-Readme $fixture.ExitConfirmedBeforeDirectoryRemoval 'directory removal preceded daemon-exit proof'
        } catch {
            if ($bodyError) {
                throw [AggregateException]::new('README body and teardown failed.',
                    [Exception[]] @($bodyError.Exception, $_.Exception))
            }
            throw
        } finally { if ($process) { $process.Dispose() } }
    }
    'PASS README installed blocks, default endpoint, graph and owned cleanup'
    return
}
Assert-Readme ($env:LIBTMUX_SOCKET_PATH -ceq $env:LIBTMUX_README_OWNED_SOCKET -and
    $env:LIBTMUX_SOCKET_PATH -cmatch '^/tmp/libtmux-powershell-[a-f0-9]{32}/socket$') 'child has no owned endpoint'

function Assert-ReadmeSessionsRemoved {
    $sessions = @($server | Get-TmuxSession)
    Assert-Readme ($sessions.Count -eq 1 -and $sessions[0].Name -ceq 'fixture') 'the example left an owned session alive'
}

$blocks = @{}
foreach ($id in @('readme.install.import', 'readme.quickstart', 'readme.endpoint', 'readme.create', 'readme.filter',
    'readme.related', 'input.run', 'input.http-ready', 'readme.control',
    'readme.workspace.01-import', 'readme.workspace.02-plan', 'readme.workspace.03-review', 'readme.workspace.04-preview',
    'readme.workspace.05-apply', 'readme.workspace.06-graph')) {
    $blocks[$id] = Get-ReadmeBlock $id
}
$priorReviewRoot = $env:LIBTMUX_REVIEW_MODULE_ROOT
try {
    $env:LIBTMUX_REVIEW_MODULE_ROOT = $moduleRootPath
    . $blocks['readme.install.import']
} finally { $env:LIBTMUX_REVIEW_MODULE_ROOT = $priorReviewRoot }
foreach ($name in @('LibTmux', 'LibTmux.Workspace')) {
    $loaded = @(Get-Module -Name $name)
    Assert-Readme ($loaded.Count -eq 1 -and
        $loaded[0].ModuleBase -ceq (Join-Path $moduleRootPath "$name/0.1.0")) "the README imported another $name module"
}
$commands = @(Get-Command -Module LibTmux -CommandType Cmdlet)
$help = Get-Help LibTmux\New-TmuxSession -Examples
Assert-Readme (@($commands | Where-Object Name -CEQ 'New-TmuxSession').Count -eq 1 -and
    $help.Examples.Example.Count -gt 0) 'installed cmdlets or help examples are not discoverable'
. $blocks['readme.endpoint']
Assert-Readme (!$server.IsMaterialized) 'the first block contacted tmux'
. $blocks['readme.create']
Assert-Readme ($captured -is [LibTmux.Session] -and $captured.Windows.Count -eq 2 -and
    $captured.Windows[0].Name -ceq 'editor' -and $captured.Windows[1].Name -ceq 'logs' -and
    $captured.Windows[0].Panes.Count -eq 2 -and
    $captured.Windows[1].Panes.Count -eq 1) 'the captured graph is incomplete after cleanup'
$selected = @(. $blocks['readme.filter'])
Assert-Readme ($selected.Count -eq 1 -and $selected[0].PaneCount -eq 2) 'the local pane pipeline returned the wrong result'
$related = @(. $blocks['readme.related'])
Assert-Readme ($related.Count -eq 1 -and
    [object]::ReferenceEquals($related[0], $captured.Windows[0])) 'the graph predicate selected a different window'
$paneRun = @(. $blocks['input.run'])
Assert-Readme ($paneRun.Count -eq 1 -and
    $paneRun[0] -is [LibTmux.PaneRunResult] -and
    $paneRun[0].ExitStatus -eq 7 -and !$paneRun[0].TimedOut) 'the shell exit status was not reported'
$httpReady = @(. $blocks['input.http-ready'])
$readyLine = 'Serving HTTP on 127\.0\.0\.1 port [0-9]+'
Assert-Readme ($httpReady.Count -eq 2 -and
    $httpReady[0] -is [LibTmux.PaneWaitResult] -and
    $httpReady[0].Outcome.ToString() -cin @('PresentAtEntry', 'Matched') -and
    ($httpReady[0].Tail -join "`n") -cmatch $readyLine -and
    $httpReady[0].EffectiveTimeout -eq [TimeSpan]::FromSeconds(10) -and
    !$httpReady[0].PollingFallback -and $httpReady[0].EventsDropped -eq 0 -and
    $httpReady[1] -eq 200) 'the HTTP service was not ready and responsive'
Assert-ReadmeSessionsRemoved
$controlReply = @(. $blocks['readme.control'])
Assert-Readme ($controlReply.Count -eq 1 -and $controlReply[0] -ceq 'control-demo') 'the control client returned a different session'
. $blocks['readme.workspace.01-import']
Assert-Readme ($workspace -is [LibTmux.Workspace.WorkspaceFile] -and
    $workspace.Windows.Count -eq 1 -and $workspace.Windows[0].Panes.Count -eq 2) 'workspace import did not preserve the two panes'
. $blocks['readme.workspace.02-plan']
$actions = @(. $blocks['readme.workspace.03-review'])
$preview = @(. $blocks['readme.workspace.04-preview'])
Assert-Readme ($workspacePlan -is [LibTmux.Workspace.WorkspacePlan] -and
    $workspacePlan.SessionName -ceq 'readme-workspace-preview' -and
    $actions.Count -eq $workspacePlan.Actions.Count -and
    @($actions | Where-Object Kind -eq 'CreateWindow').Count -eq 1 -and
    @($actions | Where-Object Kind -eq 'SplitPane').Count -eq 1 -and
    $preview.Count -eq 0) 'workspace preview did not expose its two-pane plan'
. $blocks['readme.workspace.05-apply']
$workspaceView = @(. $blocks['readme.workspace.06-graph'])
Assert-Readme ($workspaceResult -is [LibTmux.Workspace.WorkspaceResult] -and
    $workspaceResult.Session -is [LibTmux.Session] -and
    $workspaceResult.Session.Name -ceq 'readme-workspace-preview' -and
    $workspaceResult.Windows.Count -eq 1 -and
    $workspaceResult.Windows[0] -is [LibTmux.Window] -and
    $workspaceResult.Windows[0].Name -ceq 'editor' -and
    $workspaceResult.Windows[0].Panes.Count -eq 2 -and
    $workspaceResult.Windows[0].Panes[0] -is [LibTmux.Pane] -and
    $workspaceView.Count -eq 1 -and
    $workspaceView[0].Name -ceq 'editor' -and
    $workspaceView[0].PaneCount -eq 2) 'workspace apply did not return the captured native two-pane graph'
Assert-ReadmeSessionsRemoved
$priorModulePath = $env:PSModulePath
try {
    $env:PSModulePath = $moduleRootPath + [IO.Path]::PathSeparator + $priorModulePath
    $quickStartView = @(. $blocks['readme.quickstart'])
} finally { $env:PSModulePath = $priorModulePath }
Assert-Readme ($quickStartView.Count -eq 2 -and
    $quickStartView[0].Name -ceq 'editor' -and $quickStartView[0].PaneIds -cmatch '^%[0-9]+, %[0-9]+$' -and
    $quickStartView[1].Name -ceq 'logs' -and $quickStartView[1].PaneIds -cmatch '^%[0-9]+$') 'the README quick start view does not match its output'
Assert-ReadmeSessionsRemoved
