# Link and move windows between sessions

A tmux window can sit at different indices in several sessions. Read it through
the session whose placement you want to change: its `Window` handle captures
that session and index. From an [explicit endpoint](read.md), choose the source
window and destination session. The examples use `$window` and `$session` from
the same server.

Link the window into the destination session at index 5 while leaving that
session's selected window alone:

<!-- example: placement.01-link -->
```powershell
$window |
    New-TmuxWindowLink -Session $session -Index 5 -NoSelect -Confirm:$false
```

The command emits no placement handle. Read the destination session's windows
and select the new link by physical ID and destination index:

<!-- example: placement.02-select -->
```powershell
$window = $session | Get-TmuxWindow |
    Where-Object { $_.Id -eq $window.Id -and $_.Index -eq 5 }
```

`-ReplaceExisting` lets tmux displace a window already at the index, and that
window is destroyed if this was its last link.

Move the link from index 5 to index 6 in the same session. Keep the returned
replacement handle because the original still describes the old placement:

<!-- example: placement.03-move -->
```powershell
$window = $window | Move-TmuxWindow -Index 6 -PassThru -Confirm:$false
```

- `-DestinationSession $otherSession` moves the link to another session on the
  same endpoint and daemon generation.
- Without `-Index`, the next free index is used.
- `-Direction Before` or `After` inserts relative to a destination.
- `-NoSelect` keeps the destination's current selection.

Remove only this session's link to the window. Links in other sessions and
their panes remain:

<!-- example: placement.04-remove -->
```powershell
$window | Remove-TmuxWindowLink -Confirm:$false
```

Without `-KillIfLast`, tmux refuses to remove a window's final link. With it,
the final unlink destroys the window and its panes. To destroy a window and
every link on purpose, use [Remove-TmuxWindow](remove.md).

- The three commands ask for confirmation by default, and `-WhatIf` previews
  without contacting tmux.
- A stale source placement is rejected in tmux's native queue. Link and
  cross-session move also reject a destination session from another endpoint or
  daemon generation before dispatch.
- A failed move readback can follow a successful dispatch. Inspect the topology
  before retrying.

More: [command reference](reference/LibTmux/Move-TmuxWindow.md).
