param(
    [Parameter(Mandatory)] [string] $ModuleRoot,
    [Parameter(Mandatory)] [ValidateSet('absent', 'running')] [string] $InitialState,
    [Parameter(Mandatory)] [string] $OutputPath,
    [ValidateSet('success', 'body', 'hold')] [string] $Mode = 'success',
    [string] $ExampleSource,
    [string] $Document
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path (Split-Path $PSScriptRoot)
if (!$ExampleSource) { $ExampleSource = "$root/examples/QuickStart.ps1" }
if (!$Document) { $Document = "$root/README.md" }
$source = [IO.File]::ReadAllText($ExampleSource).Replace("`r`n", "`n")
$sourceHash = (Get-FileHash -LiteralPath $ExampleSource).Hash
$readme = [IO.File]::ReadAllText($Document)
$pattern = '(?ms)^<!-- example: readme.ordinary -->\r?\n```powershell\r?\n(?<code>.*?)^```[ \t]*$'
$blocks = [regex]::Matches($readme, $pattern)
if ($blocks.Count -ne 1 -or $blocks[0].Groups['code'].Value.Replace("`r`n", "`n") -cne $source) {
    throw 'The displayed ordinary example differs from examples/QuickStart.ps1.'
}
$socket = $env:LIBTMUX_SOCKET_PATH
if (!$env:LIBTMUX_SOCKET_PATH) {
    $uid = (& /usr/bin/id -u).Trim()
    $socket = Join-Path $env:TMUX_TMPDIR "tmux-$uid/$env:LIBTMUX_SOCKET_NAME"
}
if (!$socket.StartsWith($env:TMUX_TMPDIR + '/', [StringComparison]::Ordinal)) { throw 'No private test endpoint.' }
$binary = $env:LIBTMUX_TMUX
function Invoke-Native([string[]] $Arguments) {
    $reply = @(& $binary -S $socket -N @Arguments)
    if ($LASTEXITCODE) { throw "Native check failed: $($Arguments -join ' ')" }
    $reply -join "`n"
}
function Get-ExistingState {
    [ordered] @{
        Process = Invoke-Native @('display-message', '-p', '#{pid}')
        Sessions = Invoke-Native @('list-sessions', '-F', '#{session_id}|#{session_name}|#{session_windows}')
        Panes = Invoke-Native @('list-panes', '-a', '-F', '#{session_id}|#{window_id}|#{window_name}|#{pane_id}|#{pane_pid}|#{pane_title}')
        Options = Invoke-Native @('show-options', '-s')
        Interval = Invoke-Native @('show-options', '-gv', 'status-interval')
    }
}
$before = $null
if ($InitialState -eq 'running') {
    $null = Invoke-Native @('new-session', '-d', '-s', 'user-work', '-n', 'editor', '-x', '120', '-y', '50')
    $null = Invoke-Native @('split-window', '-d', '-t', '=user-work:editor')
    $null = Invoke-Native @('new-window', '-d', '-t', '=user-work:', '-n', 'logs')
    $null = Invoke-Native @('set-option', '-s', 'exit-empty', 'on')
    $null = Invoke-Native @('set-option', '-g', 'status-interval', '37')
    $before = Get-ExistingState
} elseif (Test-Path -LiteralPath $socket) { throw 'Cold-start case already has a socket.' }
if ($Mode -eq 'body') { [IO.File]::WriteAllText($env:LIBTMUX_ORDINARY_FAULT, 'body') }
$failure = $null
$observed = [ordered] @{ SourceSha256 = $sourceHash; InitialState = $InitialState; Mode = $Mode }
try {
    $session = & $ExampleSource
    if ($session -isnot [LibTmux.Session] -or $session.Name -cne 'libtmux-demo') { throw 'QuickStart did not return its native session.' }
    $loaded = @(Get-Module LibTmux)
    if ($loaded.Count -ne 1 -or $loaded[0].ModuleBase -cne "$ModuleRoot/LibTmux/0.1.0") { throw 'QuickStart imported another module.' }
    if ($session.Windows.Count -ne 2 -or ($session.Windows.Name -join ',') -cne 'editor,logs' -or
        $session.Panes.Count -ne 2) { throw 'QuickStart created the wrong graph.' }
    $nativeIds = Invoke-Native @('list-panes', '-s', '-t', '=libtmux-demo', '-F', '#{pane_id}')
    if (($session.Panes.Id -join "`n") -cne $nativeIds) { throw 'The returned graph differs from native tmux.' }
    $daemon = Invoke-Native @('display-message', '-p', '#{pid}')
    $second = & $ExampleSource
    if ($second.Id -ne $session.Id -or ($second.Panes.Id -join ',') -cne ($session.Panes.Id -join ',')) {
        throw 'Repeating the ordinary program created replacement objects.'
    }
    $again = Start-TmuxServer
    if ($again -isnot [LibTmux.Server] -or !$again.IsMaterialized -or
        (Invoke-Native @('display-message', '-p', '#{pid}')) -cne $daemon) { throw 'Ensure did not return the existing native server.' }
    $names = Invoke-Native @('list-sessions', '-F', '#{session_name}')
    $expected = if ($InitialState -eq 'running') { "libtmux-demo`nuser-work" } else { 'libtmux-demo' }
    if ($names -cne $expected) { throw "Bootstrap or repeated creation left unexpected sessions: $names" }
    if ($before) {
        $after = Get-ExistingState
        $observed.ExistingState = $before
        $observed.AfterState = $after
        $added = @($after.Options.Split("`n") | Where-Object { $_ -cnotin $before.Options.Split("`n") })
        $lost = @($before.Options.Split("`n") | Where-Object { $_ -cnotin $after.Options.Split("`n") })
        if ($after.Process -cne $before.Process -or $lost.Count -or
            @($added | Where-Object { $_ -cnotmatch '^@libtmux_owner_generation [a-f0-9]{32}$' }).Count -or
            $after.Interval -cne $before.Interval) {
            throw 'Reusing the server changed its process or configuration.'
        }
        foreach ($line in $before.Sessions.Split("`n")) { if ($line -cnotin $after.Sessions.Split("`n")) { throw 'Reusing the server changed a user session.' } }
        foreach ($line in $before.Panes.Split("`n")) { if ($line -cnotin $after.Panes.Split("`n")) { throw 'Reusing the server changed a user window or pane.' } }
    } elseif ((Invoke-Native @('show-options', '-sv', 'exit-empty')) -cne 'off') { throw 'New daemon will not remain available without sessions.' }
    $observed.DaemonPid = [int] $daemon
    $observed.SessionId = [string] $session.Id
    $observed.PaneIds = @($session.Panes.Id | ForEach-Object { [string] $_ })
    $observed.ExistingState = $before
    $observed.Passed = $true
} catch {
    $failure = $_
    $observed.Passed = $false
    $observed.Failure = $_.Exception.ToString()
    if ($Mode -eq 'body' -and $observed.Failure.Contains('injected ordinary example body failure')) {
        $partial = Invoke-Native @('list-windows', '-t', '=libtmux-demo', '-F', '#{window_name}')
        $observed.PartialWorkspaceObserved = $partial -ceq 'editor'
        if ($before) {
            $observed.ExistingState = $before
            $observed.AfterState = Get-ExistingState
            foreach ($line in $before.Panes.Split("`n")) {
                if ($line -cnotin $observed.AfterState.Panes.Split("`n")) { throw 'Body failure changed an existing user window or pane.' }
            }
        }
    }
} finally {
    if ((Get-FileHash -LiteralPath $ExampleSource).Hash -cne $sourceHash) { throw 'QuickStart source changed during execution.' }
    $observed | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath
}
if ($failure) { throw $failure }
if ($Mode -eq 'body') { throw 'Body failure injection was not observed.' }
if ($Mode -eq 'hold') { $null = Invoke-Native @('wait-for', 'ordinary-example-release') }
