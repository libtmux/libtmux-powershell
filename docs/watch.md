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
    $socketPath = $server.ConnectionOptions.SocketPath
    $tmuxBinaryPath = $server.ConnectionOptions.TmuxBinaryPath
    Start-ThreadJob -ScriptBlock {
        Import-Module LibTmux
        New-TmuxServer -SocketPath $using:socketPath -TmuxBinaryPath $using:tmuxBinaryPath |
            Watch-TmuxEvent -Target 'fixture' -MaxEvents 1 -MaxOutputBytes 1048576
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

The bundled alpha.15 core bounds the upstream queue by event count. The
watcher's handoff does not impose an aggregate byte limit on that upstream
queue. A slow consumer can receive `TmuxEventsDroppedEvent`; use a fresh
snapshot if you need current topology after loss. Stopping may consume a
record that has not reached the pipeline.

## Run independent commands concurrently

`ForEach-Object -Parallel` creates worker runspaces. Create and close each
client in the worker that uses it. This finite example emits two short replies,
and `-ThrottleLimit 2` bounds concurrent workers. Results arrive in completion
order; include an identifier in your real workload if input order matters.

<!-- example: watch.parallel -->
```powershell
& {
    $socketPath = $server.ConnectionOptions.SocketPath
    $tmuxBinaryPath = $server.ConnectionOptions.TmuxBinaryPath
    'first', 'second' | ForEach-Object -ThrottleLimit 2 -Parallel {
        Import-Module LibTmux
        $endpoint = New-TmuxServer -SocketPath $using:socketPath -TmuxBinaryPath $using:tmuxBinaryPath
        $control = $endpoint | Connect-TmuxControl -Target 'fixture' -ErrorAction Stop
        try {
            $control | Invoke-TmuxControlCommand -Command (New-TmuxCommand -Name 'display-message' -Arguments @('-p', $_)) -ErrorAction Stop
        } finally {
            $control | Disconnect-TmuxControl -Confirm:$false
        }
    }
}
```
