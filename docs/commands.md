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
    $control = $server | Connect-TmuxControl -Target 'fixture' -ErrorAction Stop
    try {
        $control | Invoke-TmuxControlCommand -Command (New-TmuxCommand -Name 'display-message' -Arguments @('-p', '#{session_name}')) -ErrorAction Stop
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
