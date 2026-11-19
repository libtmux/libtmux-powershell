# Watch events and use runspaces

`Watch-TmuxEvent` emits notifications and pane output fragments as they arrive.
One application write can span several events, and one event can hold several
lines. The stream is not a durable or byte-exact log; use
[rendered capture](capture.md) for the pane's current screen.

- **Ownership:** pass a control connection to borrow it, or a server and a raw
  `-Target` to let the watcher own a temporary client. Stop, an early pipeline
  exit and module removal end the reader, and only a client the watcher created
  is disposed. The daemon and sessions keep running.
- **Module removal:** cancels active watchers in that runspace only, and does not
  close handles from `Connect-TmuxControl`.
- **One consumer:** a connection has one event consumer. The package rejects
  competing watchers, and callers must not enumerate the same native `Events`
  stream directly.
- **Delivery:** each event reaches the pipeline callback before the next is
  fetched. Downstream code may send a control command on that connection,
  because reply processing does not wait for notification delivery.

## Observe one owned change

`Watch-TmuxEvent` attaches a control client, which needs tmux 3.7 or newer. With
a server on an older daemon it is refused before anything attaches.

[Install libtmux for PowerShell](../README.md#install-from-source), then paste
this script into PowerShell. It starts a server on a socket in a private
temporary directory and leaves your default tmux server alone.

- It connects a control client before renaming the window, so tmux queues the
  notification even if the job reads it later.
- The job emits that event, bounded by an event limit, a byte budget and a
  five-second deadline.
- The `finally` block removes the job, client, session and socket directory. If
  removing the session fails, the directory stays so the server remains
  reachable.

<!-- example: watch.owned-rename -->
```powershell
& {
    $ErrorActionPreference = 'Stop'
    Import-Module LibTmux
    $name = 'libtmux-watch-' + $PID + '-' + [Guid]::NewGuid().ToString('N')
    $socketDirectory = Join-Path ([IO.Path]::GetTempPath()) $name
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
        if (-not ($job | Wait-Job -Timeout 5)) {
            throw 'The rename notification did not arrive within five seconds.'
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
`Start-ThreadJob` returns a job at once and runs the watcher in another runspace.
Select `$server` with an absolute socket path and an executable path that runspace
can reach. This example watches an existing session named `fixture` and creates
its client inside the job.

Retained Job output needs a count and a text-byte budget, even if nobody calls
`Receive-Job`. Budgets reset for each input connection or server, so piping N
owners can emit N times `-MaxEvents`. This example uses one client and keeps at
most one event and 1048576 UTF-8 text bytes. The job completes after the first
notification; raise both limits on purpose for a longer observation.

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

Collect the result when needed, and always stop and remove the job in cleanup,
even after a failed receive. Thread jobs keep native objects in this process;
process jobs serialize results and lose live handles.

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

### Cmdlet limits

- **`-MaxEventBytes`:** 1048576 by default; bounds the single event held by the
  handoff.
- **`-MaxOutputBytes`:** counts decoded UTF-8 text in output data, pane IDs,
  notification names and arguments, and exit reasons. Numeric loss counts carry
  no text bytes.
- These limits bound text payload, not object overhead or serialized Job data.
  An event that cannot fit produces an explicit error before output, and earlier
  events stay valid.

### Native event queue

The native queue separately defaults to 512 events and 4 MiB of decoded UTF-8
payload. `ServerConnectionOptions.ControlModeEventBufferCapacity` and
`ControlModeEventBufferMaxBytes` set those positive limits before connecting.
Its bytes count output data, notification names and arguments, and exit reasons,
but not pane IDs or object overhead.

- **Count pressure:** drops the oldest output from the pane with the most queued
  output events.
- **Byte pressure:** drops from the pane with the most queued output bytes.
- **No output left:** drops the oldest notification.
- **Oversized:** an oversized event is dropped, and an oversized exit reason is
  omitted while its exit event stays.
- **Reporting:** `TmuxEventsDroppedEvent` reports each loss without blocking
  command replies. After a loss, take a fresh snapshot if you need current
  topology.
- Stopping may consume a record that had not reached the pipeline.

## Run independent commands concurrently

`ForEach-Object -Parallel` creates worker runspaces, so create and close each
client in the worker that uses it. This example emits two short replies, and
`-ThrottleLimit 2` bounds the workers. Results arrive in completion order; add an
identifier to a real workload if input order matters.

Each worker attaches its own control client, which needs tmux 3.7 or newer.
Before 3.7, one client detaching while another is still attaching ends the
server, so every worker's `Connect-TmuxControl` refuses an older daemon before
it attaches. On an older server, run the commands as
[process commands](commands.md#collect-concurrent-command-results) instead.

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
