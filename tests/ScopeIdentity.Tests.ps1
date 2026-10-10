param([Parameter(Mandatory)] [string] $ModuleRoot)

# Outer integration: stale owners must not destroy a daemon that reuses their object IDs.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module "$ModuleRoot/LibTmux/0.1.0/LibTmux.psd1"
$server = New-TmuxServer
$session = $server | Get-TmuxSession -Name 'fixture'
$window = $session | Get-TmuxWindow | Select-Object -First 1
$pane = $window | Get-TmuxPane | Select-Object -First 1
$owners = @(
    $server | ConvertTo-TmuxOwnedResource
    $session | ConvertTo-TmuxOwnedResource
    $window | ConvertTo-TmuxOwnedResource
    $pane | ConvertTo-TmuxOwnedResource
)
$server | ConvertTo-TmuxOwnedResource | Close-TmuxScope
$socket = Join-Path $env:LIBTMUX_SCOPE_SOCKET_DIRECTORY 'socket'
& tmux -S $socket --fixture-start
if ($LASTEXITCODE) { throw 'Replacement fixture did not start.' }
$replacement = New-TmuxServer
$next = $replacement | New-TmuxSession -Name 'fixture'
if ($next.Id -ne $session.Id) { throw 'Replacement did not reuse the old session ID.' }
foreach ($owner in $owners) {
    $failed = $false
    try { $owner | Close-TmuxScope } catch {
        $failed = $true
        if ($_.Exception -isnot [LibTmux.StaleServerGenerationException]) { throw }
    }
    if (!$failed -or @($replacement | Get-TmuxSession).Count -ne 1) { throw 'Stale owner destroyed its replacement.' }
    $failure = $owner | Get-TmuxScopeFailure
    if (!$failure -or $failure.CleanupFailure -isnot [LibTmux.StaleServerGenerationException]) { throw 'Stale cleanup error lost retry identity.' }
}
$owner = $replacement | New-TmuxSession -Owned -Name 'missing-socket'
$hidden = Join-Path $env:LIBTMUX_SCOPE_SOCKET_DIRECTORY 'hidden-socket'
[IO.File]::Move($socket, $hidden)
try {
    $failed = $false
    try { $owner | Close-TmuxScope } catch { $failed = $true }
    if (!$failed) { throw 'Missing socket was treated as proof that the live daemon exited.' }
} finally { [IO.File]::Move($hidden, $socket) }
$owner | Close-TmuxScope
if (@($replacement | Get-TmuxSession -Name 'missing-socket').Count) { throw 'Restored endpoint could not retry cleanup.' }
$destination = $replacement | New-TmuxSession -Owned -Name 'destination'
$windowOwner = $next | New-TmuxWindow -Owned -Name 'move-owned'
$null = $replacement | Invoke-TmuxCommand -Arguments @('move-window', '-s', $windowOwner.Value.Id.ToString(), '-t', ($destination.Value.Id.ToString() + ':1'))
$null = $replacement | Invoke-TmuxCommand -Arguments @('link-window', '-s', $windowOwner.Value.Id.ToString(), '-t', ($next.Id.ToString() + ':2'))
$windowOwner | Close-TmuxScope
if (@($next | Get-TmuxWindow).Count -ne 1 -or @($destination.Value | Get-TmuxWindow).Count -ne 1) { throw 'Owned window cleanup failed after move and link.' }
$destination | Close-TmuxScope
[pscustomobject] @{ Passed = $true; Assertions = 12 } | ConvertTo-Json -Compress
