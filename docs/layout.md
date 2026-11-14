# Arrange panes and resize windows

Select `$window` and `$pane` with `Get-TmuxWindow` and `Get-TmuxPane`. Layout
and size changes support `-WhatIf` and `-Confirm`. They emit nothing on success;
with `-PassThru` they return a replacement handle, and earlier captured objects
stay as they were.

Give a window explicit dimensions in cells:

<!-- example: layout.window-size -->
```powershell
$window | Set-TmuxWindowSize -Width 120 -Height 40 -PassThru
```

At least one dimension is required. Resizing sets `window-size` to `manual`, so
the window stops following its clients. The alternatives are mutually exclusive:

- `-Direction Right -Adjustment 5` grows an edge.
- `-Mode Expand` or `Shrink` uses the largest or smallest attached client.

Arrange existing panes side by side:

<!-- example: layout.select -->
```powershell
$window | Set-TmuxLayout -Layout 'even-horizontal' -PassThru
```

- **Presets:** `even-vertical`, `main-horizontal`, `main-vertical` and `tiled`
  also work. Unambiguous prefixes are accepted; unknown or ambiguous names fail
  before dispatch.
- **Modes:** `-Mode Next`, `Previous` or `Spread` replaces `-Layout` to cycle
  layouts or spread panes.
- **Restore:** pass a captured [`$window.Layout`][window-layout] back as
  `-Layout`. On tmux 3.7 and earlier the sizes come back but panes can rotate
  between positions.
- **JSON layout:** needs tmux 3.8; see [compatibility](compatibility.md).

Set a pane's width in a window with a horizontal split:

<!-- example: layout.pane-size -->
```powershell
$pane | Set-TmuxPaneSize -Width '40' -PassThru
```

Dimensions also accept percentages such as `'50%'`. tmux clamps sizes that do
not fit, so read the replacement handle for the result. `-Direction` with
`-Adjustment` moves a pane edge instead.

Toggle a pane's zoom:

<!-- example: layout.zoom -->
```powershell
$pane | Set-TmuxPaneSize -Zoom
```

Repeating the command turns zoom off. `-Zoom` cannot combine with a size or
direction. A stale or missing target writes a per-target error, and
`-ErrorAction Stop` ends the pipeline. Cancellation does not roll back a change
already sent.

[window-layout]: https://libtmux.org/en/csharp/latest/reference/libtmux-window-layout/
