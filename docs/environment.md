# Set the environment for new panes

A native server selects tmux's global environment; a native session selects
its local environment. Reads return that table's entries without merging
inherited values. Changes affect future processes. They do not change the
environment of a process already running in a pane.

Read a stored value from a previously selected `$session`:

<!-- example: environment.read -->
```powershell
$session | Get-TmuxEnvironment -Name 'APP_MODE'
```

Omit `-Name` to list visible entries. Results are native
`TmuxEnvironmentEntry` objects with `Name`, `Value` and `IsRemoved`.
A missing variable produces no object.

Set a value for future panes and inspect the stored result:

<!-- example: environment.set -->
```powershell
$session | Set-TmuxEnvironment -Name 'APP_MODE' -Value 'development' -PassThru
```

An empty string remains a present value. Without `-PassThru`, setting emits
no success output. `-ExpandFormats` asks tmux to expand the value as a format
before storage.

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

`-MarkRemoved` retains an entry with `IsRemoved = true` and `Value = null`.
Unsetting, marking removed and setting an empty string are distinct tmux
operations.

`Set-TmuxEnvironment -Hidden` keeps a variable available to tmux formats
but excludes it from new child environments and ordinary reads. Its native
`-PassThru` result has `Value = null` and `IsRemoved = false`; the null value
means readback is unavailable, not that the variable is empty or removed.

Set and Remove support `-WhatIf` and `-Confirm`; previews contact no server.
Errors retain the original core exception and owner. `-ErrorAction Continue`
permits later owners; `Stop` terminates the pipeline. Cancellation cannot
undo a dispatched mutation.
