param(
    [Parameter(Mandatory)] [string] $ModuleRoot,
    [switch] $FailAfterCreation
)

# Integration: a fresh process owns and reaps a daemon created by the cmdlet.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ModuleRoot = (Resolve-Path -LiteralPath $ModuleRoot).Path
Import-Module (Join-Path $ModuleRoot 'LibTmux/0.1.0/LibTmux.psd1')
Add-Type -Path "$PSScriptRoot/support/OwnedDaemonReaper.cs"
[LibTmux.Testing.OwnedDaemonReaper]::Enable()
. "$PSScriptRoot/support/OwnedTmux.ps1"

function Assert-True([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}

Assert-True (-not (Test-Path Env:TMUX) -and -not (Test-Path Env:TMUX_PANE)) 'Run startup verification in a fresh test process with TMUX and TMUX_PANE removed.'

$tmuxPath = (Get-Command tmux -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$directory = Join-Path '/tmp' ('libtmux-powershell-' + [Guid]::NewGuid().ToString('N'))
$fixture = [pscustomobject]@{
    TmuxPath = $tmuxPath
    DirectoryPath = $directory
    SocketPath = Join-Path $directory 'socket'
    CancellationToken = [Threading.CancellationToken]::None
    Closed = $false
    ClientProcesses = [Collections.Generic.List[Diagnostics.Process]]::new()
    OwnedProcessIds = [Collections.Generic.HashSet[int]]::new()
}
$daemon = $null
$paneProcess = $null
$failureObserved = $false
try {
    $null = New-Item -ItemType Directory -Path $directory
    [IO.File]::SetUnixFileMode($directory, [IO.UnixFileMode]::UserRead -bor
        [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)
    $trace = Join-Path $directory 'calls'
    $wrapper = Join-Path $directory 'tmux'
    $quotedTmux = "'" + $fixture.TmuxPath.Replace("'", "'\''") + "'"
    $quotedTrace = "'" + $trace.Replace("'", "'\''") + "'"
    @"
#!/bin/sh
printf '%s\n' tmux >> $quotedTrace
exec $quotedTmux "`$@"
"@ | Set-Content -LiteralPath $wrapper
    [IO.File]::SetUnixFileMode($wrapper, [IO.UnixFileMode]::UserRead -bor
        [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute)
    Assert-True (-not (Test-Path -LiteralPath $fixture.SocketPath)) 'Startup socket already exists.'
    $server = LibTmux\New-TmuxServer -SocketPath $fixture.SocketPath -TmuxBinaryPath $wrapper -ConfigurationFile '/dev/null'
    Assert-True (-not (Test-Path -LiteralPath $fixture.SocketPath)) 'Endpoint construction started a daemon.'
    $preview = @($server | LibTmux\New-TmuxSession -Name 'never' -WhatIf)
    Assert-True ($preview.Count -eq 0 -and -not (Test-Path $fixture.SocketPath) -and -not (Test-Path $trace)) 'Session WhatIf acquired or started tmux, or emitted a result.'
    $created = @($server | LibTmux\New-TmuxSession -Name 'first' -Command 'exec /bin/sh' -Confirm:$false)
    Assert-True ($created.Count -eq 1 -and $created[0] -is [LibTmux.Session] -and $created[0].Name -ceq 'first') 'First-session creation did not emit one captured native session.'
    $identity = Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '#{pid} #{pane_pid}')
    $ids = $identity.StdOut.Trim().Split(' ')
    $daemon = [Diagnostics.Process]::GetProcessById([int] $ids[0])
    $paneProcess = [Diagnostics.Process]::GetProcessById([int] $ids[1])
    $null = $fixture.OwnedProcessIds.Add($daemon.Id)
    $null = $fixture.OwnedProcessIds.Add($paneProcess.Id)
    Assert-True ($created[0].Generation.ProcessId -eq $daemon.Id) 'Created session carries another daemon generation.'
    Assert-True (-not $created[0].Attached) 'New session unexpectedly attached a client.'
    if ($FailAfterCreation) { throw 'deliberate startup consumer failure' }
} catch {
    if (-not $FailAfterCreation -or $_.Exception.Message -cne 'deliberate startup consumer failure') { throw }
    $failureObserved = $true
} finally {
    try {
        if (Test-Path -LiteralPath $fixture.SocketPath) {
            if (-not $daemon) {
                $identity = Invoke-OwnedTmux $fixture -Arguments @('display-message', '-p', '#{pid} #{pane_pid}') -AllowFailure
                if ($identity.ExitCode -eq 0) {
                    $ids = $identity.StdOut.Trim().Split(' ')
                    $daemon = [Diagnostics.Process]::GetProcessById([int] $ids[0])
                    $paneProcess = [Diagnostics.Process]::GetProcessById([int] $ids[1])
                    $null = $fixture.OwnedProcessIds.Add($daemon.Id)
                    $null = $fixture.OwnedProcessIds.Add($paneProcess.Id)
                }
            }
            $null = Invoke-OwnedTmux $fixture -Arguments @('kill-server') -AllowFailure
        }
    } finally {
        try {
            $cleanupErrors = [Collections.Generic.List[Exception]]::new()
            foreach ($process in @($daemon, $paneProcess)) {
                if ($process) {
                    try { [LibTmux.Testing.OwnedDaemonReaper]::Reap($process, $HangGuard) }
                    catch { $cleanupErrors.Add($_.Exception) }
                }
            }
            if ($cleanupErrors.Count) { throw [AggregateException]::new('Owned startup cleanup failed.', $cleanupErrors) }
        } finally {
            foreach ($process in @($daemon, $paneProcess) + $fixture.ClientProcesses.ToArray()) {
                if ($process) { $process.Dispose() }
            }
            if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory -Recurse -Force }
        }
    }
}
Assert-True (-not $FailAfterCreation -or $failureObserved) 'Startup failure path did not execute.'
Assert-True (-not (Test-Path -LiteralPath $directory)) 'Startup fixture directory remains.'
foreach ($processId in $fixture.OwnedProcessIds) {
    $remaining = Get-Process -Id $processId -ErrorAction SilentlyContinue
    try { Assert-True ($null -eq $remaining) 'A startup-owned process remains after teardown.' }
    finally { if ($remaining) { $remaining.Dispose() } }
}
'PASS: first-session daemon startup, detached native result and owned process reaping'
