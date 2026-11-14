# Configure and run hooks

Pass a server, session, window or pane to select a hook table, and choose a
hook the scope supports.

- Server hooks are global; tmux has no separate server table.
- `-Scope` overrides the scope and `-Global` requests global defaults.
  Pane-local hooks stay local.

Inspect a configured hook on a previously selected `$session`:

<!-- example: hooks.read -->
```powershell
$session | Get-TmuxHook -Name 'alert-bell'
```

A `TmuxHook` has a base [`Name`][tmuxhook-name] and
[`Values`][tmuxhook-values], an ordered collection of `TmuxHookEntry` objects
with [`Index`][tmuxhookentry-index] and [`Command`][tmuxhookentry-command].

- `Get-TmuxHook` accepts base names only; read `Values` for entries.
- Without `-Name`, it lists the selected table.
- A missing local hook produces no objects.

Set one indexed command and inspect the complete grouped hook:

<!-- example: hooks.set -->
```powershell
$command = 'display-message "build finished"'
$session | Set-TmuxHook -Name 'alert-bell[7]' -Command $command -PassThru
```

- The command is tmux syntax, not PowerShell. tmux normalizes it, and readback
  keeps that text so it can be passed back unchanged.
- Without `-PassThru`, setting emits nothing.
- An unindexed set replaces entries. `-Append` keeps them and lets tmux pick a
  free index, which can precede existing sparse indices. Use explicit indices
  when order matters.
- Several changes are not an atomic replacement.

Run a configured base hook without waiting for its event. `Invoke-TmuxHook` uses
tmux's target-context lookup: `-Scope` and `-Global` do not force a table, and an
indexed name does not select one entry:

<!-- example: hooks.invoke -->
```powershell
$session | Invoke-TmuxHook -Name 'alert-bell'
```

The call confirms tmux accepted it. A hook can start asynchronous work; to see
it finish, signal from the hook and wait with
[Wait-TmuxChannel](reference/LibTmux/Wait-TmuxChannel.md).

Remove one indexed entry, preserving its neighbours:

<!-- example: hooks.remove -->
```powershell
$session | Remove-TmuxHook -Name 'alert-bell[7]'
```

Use the base name to remove the whole local hook. Mutations support `-WhatIf`
and `-Confirm`, and previews do no tmux I/O. Errors keep the native owner and
core exception. `-ErrorAction Continue` lets later owners run, and
[`Stop`][erroraction-stop] ends the pipeline. Cancellation cannot undo a command
already sent.

[tmuxhook-name]: https://libtmux.org/en/csharp/latest/reference/libtmux-tmuxhook-name/
[tmuxhook-values]: https://libtmux.org/en/csharp/latest/reference/libtmux-tmuxhook-values/
[tmuxhookentry-index]: https://libtmux.org/en/csharp/latest/reference/libtmux-tmuxhookentry-index/
[tmuxhookentry-command]: https://libtmux.org/en/csharp/latest/reference/libtmux-tmuxhookentry-command/
[erroraction-stop]: https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.actionpreference#system-management-automation-actionpreference-stop
