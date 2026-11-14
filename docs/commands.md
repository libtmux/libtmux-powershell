# Commands and control clients

`New-TmuxCommand` builds a command value that keeps literal argv boundaries,
including empty arguments, spaces and punctuation, and does no I/O. A command
can still run a tmux feature that starts a shell, such as `run-shell`, and shell
programs in its arguments keep that feature's normal meaning.

- **`Connect-TmuxControl`:** needs tmux 3.7 or newer and is refused on an older
  daemon before a client attaches. Chains and raw commands need only 3.3a.
- **Buffers:** literal `delete-buffer -b` and `set-buffer -n` items need tmux
  3.4. See [optional features](compatibility.md#optional-features).

Select `$server` first ([endpoint selection](read.md)). The examples need an
existing session named `fixture` and borrow its lifetime.

## Execute an ordered chain

Build the whole array, then run it once. The result is one
`TmuxCommandResult`; read its `StandardOutputLines` or its byte-valued
`StandardOutput`. Generation and placement guards on typed request commands
survive chaining.

<!-- example: commands.chain -->
```powershell
$first = New-TmuxCommand -Name 'display-message' -Arguments @('-p', 'first')
$second = New-TmuxCommand -Name 'display-message' -Arguments @('-p', 'second')
$server | Invoke-TmuxChain -Command @($first, $second)
```

- A failure stops later commands and leaves earlier changes in place.
- Output is merged; the result does not attribute receipts to each command.
- Cancellation does not roll back work already sent, so do not retry a mutation
  just because its caller stopped waiting.
- Admission defaults to 1024 commands and 1048576 UTF-8 bytes of command names
  and argument text, plus a NUL per item. `-MaxCommands` and `-MaxInputBytes`
  change them. Transport and operating-system limits also apply, and none of
  these bound memory or reply size.

## Reuse a control client

An explicit client avoids starting a tmux client for every command, and the core
correlates concurrent replies. This example closes the client on success or
failure and leaves the server and session running.

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

- `-Target` is raw tmux target syntax, resolved when the client attaches. It
  does not carry the identity a `Session` captured. A command built from raw
  text has no identity guard either; pass a typed request's command directly
  when it supplies one.
- `Invoke-TmuxControlCommand` emits reply strings, and nothing for an empty
  reply. Ctrl+C cancels the wait, and a command already sent may still run. The
  borrowed client stays usable when it finishes.
- `Disconnect-TmuxControl` closes the client you give it, including for other
  callers sharing it. Disposal cannot be cancelled, so cleanup is awaited.
- `-WhatIf` sends nothing. A preview names the connection; the native interface
  exposes no endpoint metadata to show.
- The cmdlets run on the calling pipeline. They return no Tasks and do not free
  the prompt.

## Collect concurrent command results

Use the [finite concurrent-command recipe](../examples/ConcurrentCommands.ps1)
when independent commands need separate results. Run it from the repository root
after importing `LibTmux`. It takes command values, keeps their identity guards
and starts at most `-MaxPending` calls at once.

By default each bounded wave finishes, and its results are emitted in input
order, before the next wave starts. That bounds reordering storage but can leave
a slot idle while one command in the wave finishes. Each result carries its
zero-based [`Index`][command-example], [`Name`][command-example], `ExitCode`,
output lines, error lines and [`Utf8Bytes`][command-example].

<!-- example: commands.concurrent -->
```powershell
$commands = @(foreach ($name in @('api', 'worker', 'scheduler')) {
    New-TmuxCommand -Name 'display-message' -Arguments @('-p', $name)
})
./examples/ConcurrentCommands.ps1 -Server $server -Command $commands `
    -MaxPending 2 -MaxResultBytes 4096 -Timeout 1
```

Pass a borrowed control client to reuse its connection. `-CompletionOrder` emits
each result as a task completes; simultaneous completions have no guaranteed
order, and [`Index`][command-example] still names the input. The recipe leaves
the client open, and this example closes it:

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
            -Timeout 1 -CompletionOrder
    } finally {
        $control | Disconnect-TmuxControl -Confirm:$false
    }
}
```

### Blocking commands

On tmux 3.7 or newer, commands from one server handle share a single control
client, so a command that blocks holds the commands behind it.

- A top-level `wait-for` runs in its own process and leaves the others free.
- A `wait-for` nested in a list, such as
  `if-shell -F 1 'wait-for release ; display-message -p done'`, is not seen and
  blocks the shared client until released.
- Keep a blocking command at the top level, or set `LIBTMUX_CONTROL_TRANSPORT=0`
  before creating the server handle to send every command from its own process.

### Limits

- **Admission:** 1 to 64 commands and 1 to 16 pending calls, four by default.
- **Result text:** a cumulative budget of 64 KiB by default, counting UTF-8
  command names and output and error lines plus one byte per item. A result
  over the remaining budget is rejected before it is kept or emitted. The
  budget excludes exception diagnostics, object overhead and what a consumer
  stores.
- **Native buffers:** separate. Process transport allows 64 MiB per output or
  error stream, and the default control limits allow 4 MiB per block and 16 MiB
  per reply, so many large replies can use far more memory than
  `-MaxResultBytes`.

### Deadlines and failure

- **`-Timeout`:** one deadline for the whole batch, one second by default.
  `-CancellationToken` supplies caller-managed cancellation.
- The script waits synchronously on the calling runspace and does not promise
  immediate Ctrl+C handling.
- On failure, cancellation or consumer termination it cancels and observes every
  started task before returning. Native cleanup can run past the deadline.
- Results already emitted and mutations already sent stay.
- A command failure keeps the native exception and names its input in
  `Exception.Data['LibTmux.ConcurrentCommandIndex']`. Do not retry canceled
  mutations automatically.

[command-example]: ../examples/ConcurrentCommands.ps1
