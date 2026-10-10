# Arrange panes and resize windows

Select native `$window` and `$pane` handles with `Get-TmuxWindow` and
`Get-TmuxPane`. Layout and size changes support `-WhatIf` and `-Confirm`.
Without `-PassThru`, they emit no success output. With it, they return a native
replacement handle; previously captured objects remain unchanged.

Give a window explicit dimensions in cells:

<!-- example: layout.window-size -->
```powershell
$window | Set-TmuxWindowSize -Width 120 -Height 40 -PassThru
```

At least one dimension is required. Resizing switches `window-size` to
`manual`, so the window stops following its clients. Alternatively, use
`-Direction Right -Adjustment 5` to grow an edge, or `-Mode Expand` / `Shrink`
to use the largest / smallest attached client. These forms are mutually
exclusive.

Arrange existing panes side by side:

<!-- example: layout.select -->
```powershell
$window | Set-TmuxLayout -Layout 'even-horizontal' -PassThru
```

Other presets include `even-vertical`, `main-horizontal`, `main-vertical` and
`tiled`. Unambiguous prefixes are accepted; unknown or ambiguous names fail
before dispatch. Use `-Mode Next`, `Previous` or `Spread` instead of `-Layout`
to cycle layouts or spread panes.

A captured `$window.Layout` can be passed back as `-Layout`. On tmux 3.7 and
earlier, restoring its sizes can rotate which pane occupies a position; it
does not guarantee pane identity at each position.

Set a pane's width in a window with a horizontal split:

<!-- example: layout.pane-size -->
```powershell
$pane | Set-TmuxPaneSize -Width '40' -PassThru
```

Pane dimensions also accept percentages such as `'50%'`. tmux clamps sizes
that do not fit; inspect the replacement handle for the observed dimensions.
`-Direction` with `-Adjustment` moves a pane edge instead.

Toggle a pane's zoom:

<!-- example: layout.zoom -->
```powershell
$pane | Set-TmuxPaneSize -Zoom
```

Repeating the command turns zoom off. `-Zoom` cannot be combined with a size
or direction. A stale or disappeared target writes a per-target error;
`-ErrorAction Stop` terminates the pipeline. Cancellation does not roll back
an already dispatched change.
