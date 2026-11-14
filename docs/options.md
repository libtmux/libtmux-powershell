# Read and change options

Pass a server, session, window or pane to select its option table. Choose the
endpoint with [New-TmuxServer](reference/LibTmux/New-TmuxServer.md).

- `-Scope` overrides the table and `-Global` requests global defaults.
- Pane options stay pane-local when pane scope is requested; `-Global` does not
  make them global.
- A server handle with `-Scope Session -Global` addresses the global session
  defaults.

Read the effective key mode from a previously selected `$session`:

<!-- example: options.read -->
```powershell
$session | Get-TmuxOption -Name 'status-keys' -IncludeInherited
```

Each result is a `TmuxOption` whose [`Name`][tmuxoption-name],
[`Index`][tmuxoption-index], `Inherited` and [`Value`][tmuxoption-value] are what
tmux reported.

- Without `-Name`, the whole table is listed.
- A read lists local values; `-IncludeInherited` adds inherited ones.
- `-Quiet` makes a missing option produce no rows.
- `Where-Object` filters the rows locally.

Store a user option and return the value tmux actually stored:

<!-- example: options.set -->
```powershell
$session | Set-TmuxOption -Name '@project' -Value 'api' -PassThru
```

`-PassThru` emits a `TmuxOptionValue` whose [`Raw`][tmuxoptionvalue-raw],
[`Boolean`][tmuxoptionvalue-boolean], `Integer` and `State` fields keep tmux's
interpretation. Without it, setting emits nothing. `-Append` and `-ExpandFormat`
return the stored result, not the supplied argument. `-PreventOverwrite` asks
tmux to refuse a replacement and can produce an error.

Remove a previously stored user option:

<!-- example: options.remove -->
```powershell
$session | Remove-TmuxOption -Name '@scratch'
```

- Removing a built-in override restores inheritance.
- An empty string is a stored value, so setting `''` does not remove an option.
- An indexed name such as `command-alias[40]` reads, sets or removes that array
  entry. Listing the base name keeps sparse indices.
- tmux expands formats in option names, so `#` may not stay literal.

Set and Remove support `-WhatIf` and `-Confirm`, and previews contact no server.
Errors keep the original core exception and owner. `-ErrorAction Continue` lets
later owners run, and [`Stop`][erroraction-stop] ends the pipeline. Cancellation
cannot undo a mutation already sent, and readback is not atomic with other
clients.

[tmuxoption-name]: https://libtmux.org/en/csharp/latest/reference/libtmux-tmuxoption-name/
[tmuxoption-index]: https://libtmux.org/en/csharp/latest/reference/libtmux-tmuxoption-index/
[tmuxoption-value]: https://libtmux.org/en/csharp/latest/reference/libtmux-tmuxoption-value/
[tmuxoptionvalue-raw]: https://libtmux.org/en/csharp/latest/reference/libtmux-tmuxoptionvalue-raw/
[tmuxoptionvalue-boolean]: https://libtmux.org/en/csharp/latest/reference/libtmux-tmuxoptionvalue-boolean/
[erroraction-stop]: https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.actionpreference#system-management-automation-actionpreference-stop
