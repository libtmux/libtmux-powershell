[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Process')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Process')]
    [LibTmux.Server] $Server,
    [Parameter(Mandatory, ParameterSetName = 'Control')]
    [LibTmux.IControlModeSession] $Connection,
    [Parameter(Mandatory)]
    [ValidateCount(1, 64)]
    [ValidateNotNullOrEmpty()]
    [LibTmux.TmuxCommand[]] $Command,
    [ValidateRange(1, 16)]
    [int] $MaxPending = 4,
    [ValidateRange(1, 1048576)]
    [long] $MaxResultBytes = 65536,
    [ValidateRange(1, 30)]
    [double] $Timeout = 1,
    [Threading.CancellationToken] $CancellationToken =
        [Threading.CancellationToken]::None,
    [switch] $CompletionOrder
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$commands = [LibTmux.TmuxCommand[]] $Command.Clone()
foreach ($item in $commands) {
    if ($null -eq $item) { throw 'A concurrent command cannot be null.' }
}
if (!$PSCmdlet.ShouldProcess(
        $PSCmdlet.ParameterSetName, 'Execute bounded concurrent commands')) {
    return
}

$cancel = [Threading.CancellationTokenSource]::CreateLinkedTokenSource(
    $CancellationToken)
$cancel.CancelAfter([TimeSpan]::FromSeconds($Timeout))
$pending = [Collections.Generic.List[object]]::new()
$started = [Collections.Generic.List[Threading.Tasks.Task]]::new()
$retainedBytes = 0L
$primaryError = $null
try {
    for ($offset = 0; $offset -lt $commands.Count; $offset += $MaxPending) {
        $wave = [Collections.Generic.List[object]]::new()
        $end = [Math]::Min($commands.Count, $offset + $MaxPending)
        for ($index = $offset; $index -lt $end; $index++) {
            $cancel.Token.ThrowIfCancellationRequested()
            try {
                $task = if ($PSCmdlet.ParameterSetName -ceq 'Process') {
                    $chain = $Server.Chain().Then($commands[$index])
                    $chain.ExecuteAsync($cancel.Token)
                } else {
                    $Connection.SendAsync($commands[$index], $cancel.Token)
                }
                $started.Add($task)
                $pending.Add([pscustomobject]@{ Index = $index; Task = $task })
            } catch {
                $commandError = $_.Exception
                if ($commandError -is
                    [Management.Automation.MethodInvocationException]) {
                    $commandError = $commandError.InnerException
                }
                $commandError.Data['LibTmux.ConcurrentCommandIndex'] = $index
                throw $commandError
            }
        }
        while ($pending.Count -gt 0) {
            $tasks = [Threading.Tasks.Task[]] @($pending.Task)
            $finished = [Threading.Tasks.Task]::WhenAny($tasks).WaitAsync(
                $cancel.Token).GetAwaiter().GetResult()
            $entry = $pending | Where-Object {
                [object]::ReferenceEquals($_.Task, $finished)
            } | Select-Object -First 1
            try {
                $native = $finished.GetAwaiter().GetResult()
                if ($PSCmdlet.ParameterSetName -ceq 'Process') {
                    $stdout = [string[]] @($native.StandardOutputLines)
                    $stderr = [string[]] @($native.StandardErrorLines)
                } else {
                    $stdout = [string[]] @($native)
                    $stderr = [string[]] @()
                }
                $name = $commands[$entry.Index].Name
                $bytes = 0L
                foreach ($text in @($name) + $stdout + $stderr) {
                    $cancel.Token.ThrowIfCancellationRequested()
                    $remaining = $MaxResultBytes - $retainedBytes - $bytes
                    if ($text.Length + 1 -gt $remaining) {
                        throw 'Concurrent result text exceeds MaxResultBytes.'
                    }
                    $bytes += [Text.Encoding]::UTF8.GetByteCount($text) + 1
                    if ($bytes -gt $MaxResultBytes - $retainedBytes) {
                        throw 'Concurrent result text exceeds MaxResultBytes.'
                    }
                }
                $retainedBytes += $bytes
                $result = [pscustomobject]@{
                    Index = $entry.Index
                    Name = $name
                    ExitCode = 0
                    StandardOutputLines = $stdout
                    StandardErrorLines = $stderr
                    Utf8Bytes = $bytes
                }
                if ($CompletionOrder) { $result } else { $wave.Add($result) }
                $null = $pending.Remove($entry)
            } catch {
                $commandError = $_.Exception
                if ($commandError -is
                    [Management.Automation.MethodInvocationException]) {
                    $commandError = $commandError.InnerException
                }
                $commandError.Data['LibTmux.ConcurrentCommandIndex'] = $entry.Index
                throw $commandError
            }
        }
        if (!$CompletionOrder) {
            $wave | Sort-Object Index
        }
        $started.Clear()
    }
} catch {
    $primaryError = $_.Exception
    throw
} finally {
    $cancel.Cancel()
    foreach ($task in $started) {
        try { $null = $task.GetAwaiter().GetResult() } catch {
            if ($null -ne $primaryError) {
                $primaryError.Data['LibTmux.ConcurrentCleanupError'] =
                    $_.Exception
            }
        }
    }
    $cancel.Dispose()
}
