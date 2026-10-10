# Read and change options

Pass a native server, session, window or pane to select its option table.
Use `-Scope` to override the table and `-Global` for that scope's global
defaults. For example, a server handle with `-Scope Session -Global`
addresses global session defaults. Choose the endpoint explicitly with
[New-TmuxServer](reference/LibTmux/New-TmuxServer.md).

Read the effective key mode from a previously selected `$session`:

<!-- example: options.read -->
```powershell
$session | Get-TmuxOption -Name 'status-keys' -IncludeInherited
```

Each result is a native `TmuxOption`. Its `Name`, `Index`, `Inherited` and
`Value` describe what tmux reported. Omit `-Name` to list a table. A normal
read lists local values; `-IncludeInherited` adds inherited values.
`-Quiet` makes a missing option produce no rows. `Where-Object` filters
returned rows locally.

Store a user option and return the value tmux actually stored:

<!-- example: options.set -->
```powershell
$session | Set-TmuxOption -Name '@project' -Value 'api' -PassThru
```

`-PassThru` emits a native `TmuxOptionValue`; its `Raw`, `Boolean`,
`Integer` and `State` fields preserve tmux's interpretation. Without it,
setting emits no success output. `-Append` and `-ExpandFormat` return the
stored result, not just the supplied argument. `-PreventOverwrite` asks
tmux to refuse replacement and can produce an error.

Remove a previously stored user option:

<!-- example: options.remove -->
```powershell
$session | Remove-TmuxOption -Name '@scratch'
```

Removing a built-in override restores inheritance. An empty string is a
stored value, so setting `''` does not remove an option. Indexed names such
as `command-alias[40]` read, set or remove that specific array entry;
listing the base name preserves sparse indices. tmux expands formats in
option names, so `#` is not guaranteed literal.

Set and Remove support `-WhatIf` and `-Confirm`; previews contact no server.
Errors retain the original core exception and owner. `-ErrorAction Continue`
permits later owners; `Stop` terminates the pipeline. Cancellation cannot
undo a dispatched mutation. Readback does not make a mutation atomic with
other clients.
