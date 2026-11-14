# Inspect attached clients

Read the terminal and control clients already attached to a selected native
`$server`. A plain server handle does not attach a client or own its lifetime.

<!-- example: clients.read -->
```powershell
$server | Get-TmuxClient
```

Each result is a `Client` with [`Name`][client-name], [`Tty`][client-tty],
`IsControlClient`, `AttachedSessionId` and [`Generation`][client-generation].

- `-Name` matches an exact, case-sensitive name, with no wildcards.
- No clients, or no match, produces no objects.
- An unavailable server produces an error.

Captured fields do not change when a client switches sessions. Refresh a
selected `$client` to observe it again:

<!-- example: clients.refresh -->
```powershell
$client | Update-TmuxClient
```

This reads current data and does not redraw the terminal. Refreshing a
detached client writes the native missing-object error.

Resolve the client's current session, window and pane together:

<!-- example: clients.attachment -->
```powershell
$client | Get-TmuxClientAttachment
```

The result is a `ClientAttachment`.

- A detached client or missing session produces no output, and `Window` or
  `Pane` can be null.
- It makes several tmux reads and is not an atomic observation.
- Transport failures are errors, not empty results.

These commands only inspect clients. To detach, lock or suspend one, send a raw
tmux command. Closing a client does not remove its session or daemon.

[client-name]: https://libtmux.org/en/csharp/latest/reference/libtmux-client-name/
[client-tty]: https://libtmux.org/en/csharp/latest/reference/libtmux-client-tty/
[client-generation]: https://libtmux.org/en/csharp/latest/reference/libtmux-client-generation/
