# Configure and run hooks

Use a native server, session, window or pane to select a hook table. Server
hooks are global; tmux has no separate server hook table. Choose a hook
supported in the selected scope. `-Scope` overrides the scope and `-Global`
selects its global table.

Inspect a configured hook on a previously selected `$session`:

<!-- example: hooks.read -->
```powershell
$session | Get-TmuxHook -Name 'alert-bell'
```

Each native `TmuxHook` has a base `Name` and `Values`, an ordered collection
of `TmuxHookEntry` objects with `Index` and `Command`. Get accepts base names
only; inspect `Values` for individual entries. Omit `-Name` to list the
selected table. Missing local hooks produce no objects.

Set one indexed command and inspect the complete grouped hook:

<!-- example: hooks.set -->
```powershell
$session | Set-TmuxHook -Name 'alert-bell[7]' -Command 'display-message "build finished"' -PassThru
```

The command is tmux syntax, not PowerShell syntax. tmux normalizes it;
readback preserves that normalized text so it can be passed back unchanged.
Without `-PassThru`, setting emits no success output. An unindexed set
replaces entries. `-Append` keeps them and lets tmux choose a free index,
which may precede existing sparse indices. Use explicit indices when order
matters. Multiple changes do not form an atomic replacement.

Run a previously configured hook without waiting for its event:

<!-- example: hooks.invoke -->
```powershell
$session | Invoke-TmuxHook -Name 'alert-bell'
```

The call confirms acceptance by tmux. A hook can start asynchronous work;
use a producer signal and [Wait-TmuxChannel](reference/LibTmux/Wait-TmuxChannel.md)
to observe that work completing.

Remove one indexed entry, preserving its neighbours:

<!-- example: hooks.remove -->
```powershell
$session | Remove-TmuxHook -Name 'alert-bell[7]'
```

Use the base name to remove the local hook. Mutations support `-WhatIf` and
`-Confirm`; previews perform no tmux I/O. Errors retain the native owner and
core exception. `-ErrorAction Continue` permits later owners; `Stop`
terminates the pipeline. Cancellation cannot undo a dispatched command.
