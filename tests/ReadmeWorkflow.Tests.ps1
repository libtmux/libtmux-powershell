param([Parameter(Mandatory)] [string] $ModuleRoot)

# Outer integration: run the README blocks in order on one private named socket.
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

function Invoke-NamedTmux([string] $Binary, [string] $SocketName, [string] $Operation) {
    $start = [Diagnostics.ProcessStartInfo]::new($Binary)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in @('-L', $SocketName, $Operation)) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($start)
    try {
        if (!$process.WaitForExit(3000)) {
            $process.Kill($true)
            throw "README workflow: tmux $Operation did not finish."
        }
        $process.ExitCode
    } finally { $process.Dispose() }
}

function Invoke-QuickStart([string] $InstalledModules) {
    $fakeRoot = Join-Path ([IO.Path]::GetTempPath()) ('libtmux-readme-shadow-' + [Guid]::NewGuid().ToString('N'))
    $fakeModule = New-Item -ItemType Directory -Path (Join-Path $fakeRoot 'LibTmux/99.0.0') -Force
    New-ModuleManifest -Path (Join-Path $fakeModule.FullName 'LibTmux.psd1') -ModuleVersion '99.0.0'
    $start = [Diagnostics.ProcessStartInfo]::new([Environment]::ProcessPath)
    $start.UseShellExecute = $false
    $start.WorkingDirectory = $root
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.Environment['PSModulePath'] = $fakeRoot + [IO.Path]::PathSeparator + $InstalledModules
    $start.Environment['LIBTMUX_README_MODULE_ROOT'] = $InstalledModules
    $null = $start.Environment.Remove('TMUX')
    $null = $start.Environment.Remove('TMUX_PANE')
    $command = @'
Import-Module "$env:LIBTMUX_README_MODULE_ROOT/LibTmux/0.1.0/LibTmux.psd1" -ErrorAction Stop
$session = & ./examples/QuickStart.ps1
if ($session -isnot [LibTmux.Session]) { throw 'QuickStart did not return a native Session.' }
$loaded = @(Get-Module LibTmux)
if ($loaded.Count -ne 1 -or $loaded[0].ModuleBase -cne "$env:LIBTMUX_README_MODULE_ROOT/LibTmux/0.1.0") {
    throw 'QuickStart imported a different LibTmux module.'
}
$windows = @($session.Windows | ForEach-Object {
    if ($_ -isnot [LibTmux.Window]) { throw 'QuickStart returned a non-native Window.' }
    [pscustomobject]@{
        Name = $_.Name
        PaneIds = @($_.Panes | ForEach-Object {
            if ($_ -isnot [LibTmux.Pane]) { throw 'QuickStart returned a non-native Pane.' }
            [string] $_.Id
        })
    }
})
[pscustomobject]@{
    Name = $session.Name
    SocketName = $session.Server.ConnectionOptions.SocketName
    Windows = $windows
    PaneIds = @($session.Panes | ForEach-Object { [string] $_.Id })
} | ConvertTo-Json -Compress -Depth 5
'@
    foreach ($argument in @('-NoLogo', '-NoProfile', '-Command', $command)) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($start)
    try {
        $output = $process.StandardOutput.ReadToEndAsync()
        $errors = $process.StandardError.ReadToEndAsync()
        if (!$process.WaitForExit(10000)) {
            $process.Kill($true)
            throw 'README workflow: the runnable quick start did not finish.'
        }
        if ($process.ExitCode) { throw "README workflow: quick start failed: $($errors.GetAwaiter().GetResult())" }
        ConvertFrom-Json -InputObject $output.GetAwaiter().GetResult()
    } finally {
        $process.Dispose()
        Remove-Item -LiteralPath $fakeRoot -Recurse -Force
    }
}

$blocks = @{}
foreach ($id in @('readme.install.import', 'readme.quickstart', 'read.endpoint', 'readme.create', 'readme.filter',
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
$socketName = $null
$tmux = (Get-Command tmux -CommandType Application -ErrorAction Stop |
    Select-Object -First 1).Source
try {
    . $blocks['read.endpoint']
    $socketName = $server.ConnectionOptions.SocketName
    Assert-Readme ($socketName -cmatch '^libtmux-readme-[a-f0-9]{32}$' -and
        !$server.IsMaterialized) 'the first block did not create a private, uncontacted endpoint'
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
    Assert-Readme (
        (Invoke-NamedTmux $tmux $socketName 'list-sessions') -ne 0
    ) 'HTTP cleanup left its owned session or client running'
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
    Assert-Readme ((Invoke-NamedTmux $tmux $socketName 'list-sessions') -ne 0) 'the example left its server running'
    $quickStartPath = Join-Path $root 'examples/QuickStart.ps1'
    Assert-Readme (Test-Path -LiteralPath $quickStartPath) 'the runnable quick start is missing'
    $quickStart = @(Invoke-QuickStart $moduleRootPath)
    Assert-Readme ($quickStart.Count -eq 1 -and $quickStart[0].Name -ceq 'demo' -and
        $quickStart[0].Windows.Count -eq 2 -and
        $quickStart[0].Windows[0].Name -ceq 'editor' -and
        $quickStart[0].Windows[0].PaneIds.Count -eq 2 -and
        $quickStart[0].Windows[1].Name -ceq 'logs' -and
        $quickStart[0].Windows[1].PaneIds.Count -eq 1 -and
        $quickStart[0].PaneIds.Count -eq 3 -and
        @($quickStart[0].PaneIds | Select-Object -Unique).Count -eq 3 -and
        @($quickStart[0].PaneIds | Where-Object { $_ -notmatch '^%\d+$' }).Count -eq 0) 'the runnable quick start returned a different native graph'
    Assert-Readme ((Invoke-NamedTmux $tmux $quickStart[0].SocketName 'list-sessions') -ne 0) 'the runnable quick start left its server running'
    $priorModulePath = $env:PSModulePath
    try {
        $env:PSModulePath = $moduleRootPath + [IO.Path]::PathSeparator + $priorModulePath
        $quickStartView = @(. $blocks['readme.quickstart'])
    } finally { $env:PSModulePath = $priorModulePath }
    Assert-Readme ($quickStartView.Count -eq 2 -and
        $quickStartView[0].Name -ceq 'editor' -and $quickStartView[0].PaneIds -ceq '%0, %1' -and
        $quickStartView[1].Name -ceq 'logs' -and $quickStartView[1].PaneIds -ceq '%2') 'the README quick start view does not match its output'
} finally {
    if ($socketName -and (Invoke-NamedTmux $tmux $socketName 'list-sessions') -eq 0) {
        $null = Invoke-NamedTmux $tmux $socketName 'kill-server'
    }
}

'PASS README installed blocks, graph, captured output and named-socket cleanup'
