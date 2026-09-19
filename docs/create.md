# Create sessions, windows and panes

`New-TmuxSession`, `New-TmuxWindow` and `Split-TmuxPane` create tmux objects
and emit native `LibTmux.Session`, `LibTmux.Window` and `LibTmux.Pane`
handles. Each requires its native owner directly or through the pipeline:
a server for a session, a session for a window and a pane for a split.
Use [explicit endpoints and selection](read.md) to choose those owners.

Creation supports `-WhatIf` and `-Confirm`. Confirmation occurs before
discovery or dispatch, including when creating the first session would start
a daemon. A preview emits no created object. Creating objects does not
transfer daemon ownership to the module or arrange automatic teardown.
Choose an endpoint you control and remove the created resources when done.

## Create a detached session

The following command assumes `$server` is an endpoint you own. It creates a
detached session with the requested window name and dimensions:

<!-- example: create.session -->
```powershell
$session = $server | New-TmuxSession -Name 'work' -WindowName 'editor' -Width 100 -Height 30
```

Omitting `-Name` lets tmux choose a name. An existing name remains an error;
this command does not replace or attach to an existing session. Omitting
dimensions retains tmux's defaults. Names and working directories retain
tmux's format expansion rules, including the meaning of `#`.

Dimensions remain subject to tmux's `window-size` policy. On tmux 3.2a,
detached creation can use the command client's dimensions unless
`window-size` is `manual`.

## Create a window or split

Create a window at an explicit nonnegative index and make it current:

<!-- example: create.window -->
```powershell
$window = $session | New-TmuxWindow -Name 'tools' -Index 5 -Activate
```

Omitting `-Index` lets tmux choose an available index. An occupied index
remains an error. New windows stay unselected unless `-Activate` is present;
selecting one does not attach a PowerShell process to the terminal.

Given a selected native `$pane`, place a new pane to its left and request
twenty columns:

<!-- example: create.split -->
```powershell
$newPane = $pane | Split-TmuxPane -Horizontal -Before -Size 20
```

Splits default to a new pane below the target. `-Horizontal` selects a
left/right split; `-Before` puts the new pane above or left of the target.
Use either positive `-Size` cells or `-Percentage` from 1 through 100.
Omitting both uses tmux's default split size. Geometry still must fit the
available window. `-FullWindow` spans the full window and `-Zoom` requests
zooming the new pane. `-Activate` selects it; otherwise the previously active
pane stays active. The core owns tmux flag generation and version capability
behavior.

## Commands, directories and environment

All three cmdlets accept `-Command`, `-StartDirectory` and `-Environment`.
`-Command` is one tmux shell-command string. tmux runs it through its shell;
quote shell syntax deliberately and keep untrusted input out of that string.
Omitting it uses the configured tmux default command or shell. For example,
on a Unix host with `/bin/sh` available:

<!-- example: create.command -->
```powershell
$window = $session | New-TmuxWindow -Name 'shell' -Command 'exec /bin/sh'
```

`-StartDirectory` is a filesystem path interpreted by the core and tmux.
Use an absolute path for predictable behavior. The core expands `~` and
`~/`; the adapter does not resolve PowerShell provider paths or change the
caller's current directory. tmux may expand formats within the path.

`-Environment` accepts a dictionary of string keys and string values.
Empty values are retained; numeric and null values are rejected before
dispatch with `Tmux.InvalidCreation`. Names cannot be empty or contain `=`
or NUL; values cannot contain NUL. Validation also applies to `-WhatIf`.
Entries are copied before processing
owners. They become tmux's per-session or per-process environment entries;
the PowerShell host environment remains unchanged. Spaces, quotes and
semicolons in each value remain part of that argument.

<!-- example: create.environment -->
```powershell
$window = $session | New-TmuxWindow -Environment @{ APP_MODE = 'development'; OPTIONAL = '' }
```

## Failures and results

Success emits the core's captured created object. Keep that returned handle
when later work needs its current metadata; an existing owner handle is not
refreshed in place. An empty owner pipeline emits nothing. Wrap a pipeline in
`@(...)` when the caller needs an array for zero, one or many results.
Creation errors use `Tmux.SessionCreateFailed`,
`Tmux.WindowCreateFailed` and `Tmux.PaneSplitFailed`, retain the original core
exception and failed owner, and allow later pipeline owners to continue
under `-ErrorAction Continue`. `-ErrorAction Stop` stops at the first error.
Cancellation reaches the core operation; it does not roll back creation or
terminate a command already started in a pane. No mutation is retried.

The [creation integration test](../tests/Create.Tests.ps1) exercises native
return types, literal names and environment values, directory and geometry
requests, zero-dispatch previews and per-owner failures on an owned server.
The [startup integration test](../tests/CreateStartup.Tests.ps1) separately
verifies first-session daemon creation and owned process teardown. Its Linux
child-reaper setting is confined to that disposable test process.
