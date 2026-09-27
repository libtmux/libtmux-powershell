param([Parameter(Mandatory)] [string] $ModuleRoot)

# Outer integration: run the README blocks in order on one private named socket.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot
$readme = [IO.File]::ReadAllText("$root/README.md")
$moduleRootPath = (Resolve-Path -LiteralPath $ModuleRoot).Path
Import-Module (Join-Path $moduleRootPath 'LibTmux/0.1.0/LibTmux.psd1') -ErrorAction Stop
Import-Module (Join-Path $moduleRootPath 'LibTmux.Workspace/0.1.0/LibTmux.Workspace.psd1') -ErrorAction Stop

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

$commands = @(Get-Command -Module LibTmux -CommandType Cmdlet)
$help = Get-Help LibTmux\New-TmuxSession -Examples
Assert-Readme (@($commands | Where-Object Name -CEQ 'New-TmuxSession').Count -eq 1 -and
    $help.Examples.Example.Count -gt 0) 'installed cmdlets or help examples are not discoverable'

$blocks = @{}
foreach ($id in @('read.endpoint', 'readme.create', 'readme.filter', 'readme.related', 'readme.input',
    'readme.workspace.01-import', 'readme.workspace.02-plan', 'readme.workspace.03-review', 'readme.workspace.04-preview')) {
    $blocks[$id] = Get-ReadmeBlock $id
}
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
    $lines = @(. $blocks['readme.input'])
    Assert-Readme ($lines -ccontains 'hello from PowerShell') 'the signalled output was not captured'
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
    Assert-Readme ((Invoke-NamedTmux $tmux $socketName 'list-sessions') -ne 0) 'the example left its server running'
} finally {
    if ($socketName -and (Invoke-NamedTmux $tmux $socketName 'list-sessions') -eq 0) {
        $null = Invoke-NamedTmux $tmux $socketName 'kill-server'
    }
}

'PASS README installed blocks, graph, captured output and named-socket cleanup'
