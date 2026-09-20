# Inspect attached clients

Read the terminal and control clients already attached to a selected native
`$server`. A plain server handle does not attach a client or own its lifetime.

<!-- example: clients.read -->
```powershell
$server | Get-TmuxClient
```

Results are native `Client` objects with `Name`, `Tty`, `IsControlClient`,
`AttachedSessionId` and `Generation`. `-Name` selects an exact, case-sensitive
name; it does not interpret wildcards. No clients or no match produces no
objects. An unavailable server produces an error.

Captured fields stay unchanged when a client switches sessions. Refresh a
previously selected `$client` to obtain a new observation:

<!-- example: clients.refresh -->
```powershell
$client | Update-TmuxClient
```

This reads current data; it does not redraw the terminal. Refreshing a client
that has detached writes the native missing-object error.

Resolve the client's current session, window and pane together:

<!-- example: clients.attachment -->
```powershell
$client | Get-TmuxClientAttachment
```

The result is a native `ClientAttachment`. A detached client or missing
session produces no output; `Window` or `Pane` can be null. The operation
performs several tmux reads and does not promise an atomic observation.
Transport failures remain errors, not empty results.

These commands only inspect clients. Detachment, locking and suspension
remain available through explicit raw tmux commands. Closing or removing a
client must not be confused with removing its session or daemon.
