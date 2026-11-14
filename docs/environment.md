# Set the environment for new panes

A server selects tmux's global environment and a session selects its local one.

- Reads return that table's entries without merging inherited values.
- Changes affect future processes, not one already running in a pane.

Read a stored value from a previously selected `$session`:

<!-- example: environment.read -->
```powershell
$session | Get-TmuxEnvironment -Name 'APP_MODE'
```

Without `-Name`, it lists visible entries. Each is a `TmuxEnvironmentEntry` with
[`Name`][tmuxenvironmententry-name], [`Value`][tmuxenvironmententry-value] and
`IsRemoved`. A missing variable produces no object.

Set a value for future panes and inspect the stored result:

<!-- example: environment.set -->
```powershell
$session | Set-TmuxEnvironment -Name 'APP_MODE' -Value 'development' -PassThru
```

An empty string is still a value. Without `-PassThru`, setting emits nothing.
`-ExpandFormats` asks tmux to expand the value as a format before storing it.

Forget the local entry so a global value can apply again:

<!-- example: environment.unset -->
```powershell
$session | Remove-TmuxEnvironment -Name 'APP_MODE'
```

Suppress inherited values in new pane processes instead:

<!-- example: environment.mark-removed -->
```powershell
$session | Remove-TmuxEnvironment -Name 'APP_MODE' -MarkRemoved
```

`-MarkRemoved` keeps an entry with `IsRemoved = true` and `Value = null`.
Unsetting, marking removed and setting an empty string are three different tmux
operations.

`Set-TmuxEnvironment -Hidden` keeps a variable available to tmux formats but
leaves it out of new child environments and ordinary reads. Its `-PassThru`
result has `Value = null` and `IsRemoved = false`; null means readback is
unavailable, not that the variable is empty or removed.

Set and Remove support `-WhatIf` and `-Confirm`, and previews contact no server.
Errors keep the original core exception and owner. `-ErrorAction Continue` lets
later owners run, and [`Stop`][erroraction-stop] ends the pipeline. Cancellation
cannot undo a mutation already sent.

[tmuxenvironmententry-name]: https://libtmux.org/en/csharp/latest/reference/libtmux-tmuxenvironmententry-name/
[tmuxenvironmententry-value]: https://libtmux.org/en/csharp/latest/reference/libtmux-tmuxenvironmententry-value/
[erroraction-stop]: https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.actionpreference#system-management-automation-actionpreference-stop
