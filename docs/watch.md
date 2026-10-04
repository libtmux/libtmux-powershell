# Watch events and use runspaces

`Watch-TmuxEvent` emits native notifications and pane output fragments as they
arrive. One application write may span several events, and one event may
contain multiple lines. Use [rendered capture](capture.md) when you need the
pane's current screen.
The stream is not a durable or byte-exact log.

Supply a control connection to borrow it, or a server and raw `-Target` to let
the watcher own a temporary client. Stop, early pipeline exit and module removal
end the reader; only an internally created client is disposed. The tmux daemon
and sessions remain running. Removing the module cancels active watchers only
in that runspace, and does not close handles returned by `Connect-TmuxControl`.

One connection has one event consumer. The package rejects competing watchers;
callers must also avoid directly enumerating the same native `Events` stream.
Each event is delivered on the pipeline callback before another is fetched.
Downstream code may synchronously send a control command on that connection:
reply processing does not wait for notification delivery.

## Observe one owned change

After [installing libtmux for PowerShell](../README.md#install-from-source),
paste this script into PowerShell. It creates one session on a socket in a
private directory under `/tmp`, which keeps the socket path short enough for
macOS. It connects a control client before renaming the
window, so tmux queues the notification even if the job reads it later. The job
emits that native event. An event limit, byte budget and five-second deadline
bound the observation. The finally block removes the job, client, session and
socket directory. If session removal fails, the directory remains so the
server is reachable. The default tmux server is untouched.

<!-- example: watch.owned-rename -->
```powershell
& {
    $ErrorActionPreference = 'Stop'
    Import-Module LibTmux
    $name = 'libtmux-watch-' + $PID + '-' + [Guid]::NewGuid().ToString('N')
    $socketDirectory = Join-Path '/tmp' $name
    $null = New-Item $socketDirectory -ItemType Directory -ErrorAction Stop
    $ownerOnly = [IO.UnixFileMode]::UserRead -bor
        [IO.UnixFileMode]::UserWrite -bor
        [IO.UnixFileMode]::UserExecute
    [IO.File]::SetUnixFileMode($socketDirectory, $ownerOnly)
    $socketPath = Join-Path $socketDirectory 'socket'
    $options = @{ SocketPath = $socketPath; ConfigurationFile = '/dev/null' }
    $server = New-TmuxServer @options
    $session = $control = $job = $null
    try {
        $session = $server | New-TmuxSession `
            -Name watch-demo -WindowName before -Command 'exec /bin/cat'
        $control = $server |
            Connect-TmuxControl -Target $session.Name -ErrorAction Stop
        $job = Start-ThreadJob -ScriptBlock {
            Import-Module LibTmux
            $using:control |
                Watch-TmuxEvent -MaxEvents 16 -MaxOutputBytes 1MB |
                Where-Object {
                    $_ -is [LibTmux.TmuxNotificationEvent] -and
                    $_.Name -ceq 'window-renamed' -and
                    $_.Arguments -ccontains 'after'
                } |
                Select-Object -First 1
        }
        $null = $server | Invoke-TmuxCommand -Arguments @(
            'rename-window', '-t', 'watch-demo:0', 'after'
        )
        if (-not ($job | Wait-Job -Timeout 30)) {
            throw 'The rename notification did not arrive in time.'
        }
        $notification = $job | Receive-Job -ErrorAction Stop
        if ($null -eq $notification) {
            throw 'The watcher ended without the rename notification.'
        }
        $notification
    } finally {
        try {
            if ($job) {
                $job | Stop-Job
                $job | Remove-Job
            }
        } finally {
            try {
                if ($control) {
                    $control | Disconnect-TmuxControl -Confirm:$false
                }
            } finally {
                if ($session) { $session | Remove-TmuxSession -Confirm:$false }
                if ($session -or -not (Test-Path -LiteralPath $socketPath)) {
                    Remove-Item -LiteralPath $socketDirectory -Recurse -Force
                }
            }
        }
    }
}
```

## Bound background output

A foreground watcher occupies its pipeline until it ends or you press Ctrl+C.
`Start-ThreadJob` returns a job immediately and runs the watcher in another
runspace. Select `$server` with an absolute socket path and an executable path
available to that runspace; the following example watches an existing session
named `fixture`. It creates its client inside the job.

Retained Job output needs both a count and a text-byte budget, even if nobody
calls `Receive-Job`. Budgets reset for each input connection or server;
piping N owners can emit N times `-MaxEvents`. This example uses one client
and retains at most one event and 1048576 UTF-8
text bytes. The job completes after the initial notification; increase both
limits deliberately for a longer observation.

<!-- example: watch.job-create -->
```powershell
$job = & {
    $path = $server.ConnectionOptions.SocketPath
    $binary = $server.ConnectionOptions.TmuxBinaryPath
    Start-ThreadJob -ScriptBlock {
        Import-Module LibTmux
        New-TmuxServer -SocketPath $using:path -TmuxBinaryPath $using:binary |
            Watch-TmuxEvent -Target 'fixture' -MaxEvents 1 -MaxOutputBytes 1MB
    }
}
```

Collect the result when needed. Always stop and remove the job in cleanup,
including after a failed receive. Thread jobs preserve native objects in this
process; process jobs serialize results and do not preserve live handles.

<!-- example: watch.job-receive -->
```powershell
& {
    try {
        $job | Receive-Job -Wait -ErrorAction Stop
    } finally {
        $job | Stop-Job
        $job | Remove-Job
    }
}
```

`-MaxEventBytes` defaults to 1048576 and bounds the single event held by the
handoff. `-MaxOutputBytes` counts decoded UTF-8 text in output data, pane IDs,
notification names and arguments, and exit reasons. Numeric loss counts carry
no text bytes. These limits bound text payload, not object overhead or the
size of serialized Job data. An event that cannot fit produces an explicit
error before output; earlier events remain valid.

The native upstream queue separately defaults to 512 events and 4 MiB of
decoded UTF-8 payload. `ServerConnectionOptions.ControlModeEventBufferCapacity`
and `ControlModeEventBufferMaxBytes` configure those positive limits before
connecting. Its byte accounting includes output data, notification names and
arguments, and exit reasons; it excludes pane IDs and object overhead.
The oldest events are discarded until both queue limits hold. An oversized
event is dropped; an oversized exit reason is omitted while the exit event
is retained. `TmuxEventsDroppedEvent` reports each loss without blocking
command replies. Use a fresh snapshot when current topology matters after
loss. Stopping may consume a record that has not reached the pipeline.

## Run independent commands concurrently

`ForEach-Object -Parallel` creates worker runspaces. Create and close each
client in the worker that uses it. This finite example emits two short replies,
and `-ThrottleLimit 2` bounds concurrent workers. Results arrive in completion
order; include an identifier in your real workload if input order matters.

<!-- example: watch.parallel -->
```powershell
& {
    $path = $server.ConnectionOptions.SocketPath
    $binary = $server.ConnectionOptions.TmuxBinaryPath
    'first', 'second' | ForEach-Object -ThrottleLimit 2 -Parallel {
        Import-Module LibTmux
        $options = @{ SocketPath = $using:path; TmuxBinaryPath = $using:binary }
        $endpoint = New-TmuxServer @options
        $control = $endpoint |
            Connect-TmuxControl -Target 'fixture' -ErrorAction Stop
        try {
            $command = New-TmuxCommand -Name 'display-message' -Arguments @(
                '-p', $_
            )
            $control |
                Invoke-TmuxControlCommand -Command $command -ErrorAction Stop
        } finally {
            $control | Disconnect-TmuxControl -Confirm:$false
        }
    }
}
```
