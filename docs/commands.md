# Commands and control clients

Use native command values when composing operations. `New-TmuxCommand` keeps
literal argv boundaries, including empty arguments, spaces and punctuation;
it does no I/O. Commands can still invoke tmux features that deliberately run
a shell, such as `run-shell`. Shell programs inside those arguments retain
those features' normal semantics.

Select `$server` first using [explicit endpoint selection](read.md). These
examples require an existing session named `fixture` and borrow its lifetime.

## Execute an ordered chain

Construct the complete array, then execute it once. The result is one native
`TmuxCommandResult`; read its `StandardOutputLines` or byte-valued
`StandardOutput`. Generation and placement guards on typed request commands
survive chaining.

<!-- example: commands.chain -->
```powershell
$first = New-TmuxCommand -Name 'display-message' -Arguments @('-p', 'first')
$second = New-TmuxCommand -Name 'display-message' -Arguments @('-p', 'second')
$server | Invoke-TmuxChain -Command @($first, $second)
```

A failure stops later commands, but leaves earlier mutations in place.
Output is merged; the result does not attribute separate receipts to each
command. Cancellation does not roll back dispatched work. Do not retry a
mutation merely because its caller stopped waiting.

Admission defaults to 1024 commands and 1048576 UTF-8 bytes of command names
and argument text, counting a NUL terminator per item. `-MaxCommands` and
`-MaxInputBytes` adjust those limits. Native transport and operating-system
limits also apply. These admission limits are not memory or reply-size bounds.

## Reuse a control client

An explicit client avoids starting a new tmux client for every command. The
native core correlates concurrent replies. Keep its ownership scope visible:
this example closes the client on success or failure and leaves the tmux
server and session running.

<!-- example: commands.control -->
```powershell
& {
    $control = $server |
        Connect-TmuxControl -Target 'fixture' -ErrorAction Stop
    try {
        $command = New-TmuxCommand -Name 'display-message' -Arguments @(
            '-p', '#{session_name}'
        )
        $control |
            Invoke-TmuxControlCommand -Command $command -ErrorAction Stop
    } finally {
        $control | Disconnect-TmuxControl -Confirm:$false
    }
}
```

`-Target` is raw tmux target syntax, resolved at attachment time. It does not
carry the identity captured by a native `Session`. A command constructed
from raw text likewise has no entity identity guard; pass a native typed
request's command directly when it supplies one.

`Invoke-TmuxControlCommand` emits native reply strings and emits nothing for
an empty reply. Ctrl+C cancels the current wait; a command already dispatched
may still run. The borrowed client remains usable when that command finishes.
`Disconnect-TmuxControl` explicitly closes the supplied client, including for
other callers sharing it. Its native disposal has no cancellation token, so
cleanup is awaited.

`-WhatIf` performs no dispatch. Previewing a supplied control connection names
that connection; its native interface exposes no endpoint metadata to display.
The cmdlets run on the calling pipeline. They do not return Tasks or claim
that a foreground command leaves the prompt available.

## Collect concurrent command results

Use the [finite concurrent-command recipe](../examples/ConcurrentCommands.ps1)
when independent commands need separate results. Run it from the repository
root after importing `LibTmux`. It accepts native command values, preserves
their identity guards and starts at most `-MaxPending` calls at once.

By default, each bounded wave finishes before its results are emitted in input
order. The next wave then starts. This bounds reordering storage but can leave
a slot idle while another command in the wave finishes. Each result carries
its zero-based `Index`, `Name`, `ExitCode`, output lines, error lines and
`Utf8Bytes`.

<!-- example: commands.concurrent -->
```powershell
$commands = @(foreach ($name in @('api', 'worker', 'scheduler')) {
    New-TmuxCommand -Name 'display-message' -Arguments @('-p', $name)
})
./examples/ConcurrentCommands.ps1 -Server $server -Command $commands `
    -MaxPending 2 -MaxResultBytes 4096 -Timeout 30
```

Pass a borrowed control client to reuse its connection. `-CompletionOrder`
emits each result as the caller harvests a completed task; simultaneous
completions have no guaranteed order. `Index` still identifies its input.
The recipe leaves the client open; its owner closes it here.

<!-- example: commands.concurrent-control -->
```powershell
& {
    $control = $server |
        Connect-TmuxControl -Target 'fixture' -ErrorAction Stop
    try {
        $commands = @(foreach ($format in @(
                '#{session_name}', '#{window_name}', '#{pane_id}')) {
            New-TmuxCommand -Name 'display-message' -Arguments @(
                '-p', '-t', 'fixture:0.0', $format
            )
        })
        ./examples/ConcurrentCommands.ps1 -Connection $control `
            -Command $commands -MaxPending 2 -MaxResultBytes 4096 `
            -Timeout 30 -CompletionOrder
    } finally {
        $control | Disconnect-TmuxControl -Confirm:$false
    }
}
```

The recipe admits 1–64 commands and 1–16 pending calls; the default is four
pending calls. Its cumulative result-text budget defaults to 64 KiB, counting
UTF-8 command names and output/error lines plus one byte per item. A result
that exceeds the remaining budget is rejected before being retained or
emitted. This excludes exception diagnostics, object overhead and downstream
consumer storage. Native buffers are separate: process transport allows
64 MiB per output/error stream; default control limits allow 4 MiB per block
and 16 MiB per reply. High concurrency with large replies can therefore use
substantially more memory than `-MaxResultBytes`.

`-Timeout` supplies one deadline for the entire batch, defaulting to one
second. Supply `-CancellationToken` for caller-managed cancellation. The
script waits synchronously on the calling runspace; it does not promise
immediate Ctrl+C handling. On failure, cancellation or consumer termination,
it cancels and observes every started task before returning; native cleanup
may extend beyond the deadline. Previously emitted results and dispatched
mutations remain. Command failures retain the native exception and identify
their input with `Exception.Data['LibTmux.ConcurrentCommandIndex']`. Do not
automatically retry canceled mutations.
