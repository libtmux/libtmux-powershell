# Create sessions, windows and panes

`New-TmuxSession`, `New-TmuxWindow` and `Split-TmuxPane` create tmux objects
and emit a `LibTmux.Session`, `LibTmux.Window` or `LibTmux.Pane`. Each takes its
owner directly or from the pipeline: a server for a session, a session for a
window and a pane for a split. [Read tmux objects](read.md) shows how to choose
the owner.

- **Preview:** creation supports `-WhatIf` and `-Confirm`. Confirmation comes
  before discovery or dispatch, even when the first session would start a
  daemon. A preview emits no object.
- **Ownership:** creating objects does not give the module the daemon or
  schedule teardown. Use an endpoint you control and remove what you create.

## Create a detached session

The following command assumes `$server` is an endpoint you own. It creates a
detached session with the requested window name and dimensions:

<!-- example: create.session -->
```powershell
$session = $server |
    New-TmuxSession -Name 'work' -WindowName 'editor' -Width 100 -Height 30
```

- Without `-Name`, tmux chooses one. An existing name is an error: the command
  never replaces or attaches to a session.
- Without dimensions, tmux's defaults apply, and its `window-size` policy still
  governs them.
- Names and working directories keep tmux's format expansion, including the
  meaning of `#`.

## Create a window or split

Create a window at an explicit nonnegative index and make it current:

<!-- example: create.window -->
```powershell
$window = $session | New-TmuxWindow -Name 'tools' -Index 5 -Activate
```

Without `-Index`, tmux chooses a free one; an occupied index is an error. A new
window stays unselected unless `-Activate` is present, and selecting one does
not attach your terminal.

Given a selected native `$pane`, place a new pane to its left and request
twenty columns:

<!-- example: create.split -->
```powershell
$newPane = $pane | Split-TmuxPane -Horizontal -Before -Size 20
```

- **Direction:** a split puts the new pane below the target. `-Horizontal` makes
  a left/right split, and `-Before` puts the pane above or to the left.
- **Size:** `-Size` takes positive cells and `-Percentage` takes 1 through 100.
  With neither, tmux's default applies. The geometry must fit the window.
- **Shape:** `-FullWindow` spans the whole window, and `-Zoom` zooms the new
  pane.
- **Selection:** `-Activate` selects the new pane; otherwise the active pane
  stays.

## Commands, directories and environment

All three cmdlets accept `-Command`, `-StartDirectory` and `-Environment`.
`-Command` is one tmux shell-command string that tmux runs through its shell, so
quote shell syntax deliberately and keep untrusted input out of it. Without it,
tmux uses its default command or shell. For example:

<!-- example: create.command -->
```powershell
$window = $session | New-TmuxWindow -Name 'shell' -Command 'exec /bin/sh'
```

- **`-StartDirectory`** is a filesystem path that the core and tmux interpret.
  Use an absolute path. The core expands `~` and `~/`. PowerShell provider paths
  are not resolved, your current directory does not change, and tmux may expand
  formats in the path.
- **`-Environment`** takes a dictionary of string keys and values. Empty values
  are kept. Numeric and null values fail before dispatch with
  [`Tmux.InvalidCreation`][newtmuxsessioncommand], as do empty names, names with
  `=` or NUL, and values with NUL. Validation applies to `-WhatIf` too.
- Entries are copied before any owner is processed. They become tmux's
  per-session or per-process environment and leave the PowerShell host
  environment alone. Spaces, quotes and semicolons in a value stay in that one
  argument.

<!-- example: create.environment -->
```powershell
$window = $session | New-TmuxWindow -Environment @{
    APP_MODE = 'development'
    OPTIONAL = ''
}
```

## Failures and results

- **Success:** emits the created object as the core captured it. Keep it when
  you need its metadata later; an existing owner handle is not refreshed in
  place.
- **Empty owner pipeline:** emits nothing. Wrap a pipeline in `@(...)` when you
  need an array for zero, one or many results.
- **Errors:** [`Tmux.SessionCreateFailed`][newtmuxsessioncommand],
  [`Tmux.WindowCreateFailed`][newtmuxwindowcommand] and
  [`Tmux.PaneSplitFailed`][splittmuxpanecommand] keep the original exception and
  the failed owner. Later owners continue under `-ErrorAction Continue`, and
  `-ErrorAction Stop` stops at the first error.
- **Cancellation:** reaches the core operation. It does not roll back a
  creation or stop a command already running in a pane. No mutation is retried.

[newtmuxsessioncommand]: ../src/LibTmux.PowerShell/NewTmuxSessionCommand.cs
[newtmuxwindowcommand]: ../src/LibTmux.PowerShell/NewTmuxWindowCommand.cs
[splittmuxpanecommand]: ../src/LibTmux.PowerShell/SplitTmuxPaneCommand.cs
