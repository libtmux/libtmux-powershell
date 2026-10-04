# Link and move windows between sessions

A tmux window can appear at different indices in several sessions. Read the
window through the session whose placement you intend to change; its native
`Window` handle captures that session and index. Start from an
[explicit endpoint](read.md), then choose the source window and destination
session. The examples below use `$window` and `$session` from the same server.

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

`-ReplaceExisting` permits tmux to displace a window already at the index;
it may destroy that window when this was its last link.

Move the link from index 5 to index 6 in the same session. Keep the returned
replacement handle because the original still describes the old placement:

<!-- example: placement.03-move -->
```powershell
$window = $window | Move-TmuxWindow -Index 6 -PassThru -Confirm:$false
```

Use `-DestinationSession $otherSession` to move a link to another session on
the same endpoint and daemon generation. Omit `-Index` to use the next free
index. `-Direction Before` or `After` inserts relative to a destination;
`-NoSelect` keeps the destination's current selection.

Remove only this session's link to the window. Links in other sessions and
their panes remain:

<!-- example: placement.04-remove -->
```powershell
$window | Remove-TmuxWindowLink -Confirm:$false
```

Without `-KillIfLast`, tmux refuses to remove a window's final link. With it,
the final unlink destroys the physical window and its panes. To destroy the
window and every link deliberately, use [Remove-TmuxWindow](remove.md).

These three commands request confirmation by default. Use `-WhatIf` to
preview without contacting tmux. They reject a stale source placement in
tmux's native queue; link and cross-session move also reject destination
sessions from another endpoint or daemon generation before dispatch. A failed
move readback can follow a successful dispatch, so inspect current topology
before retrying. See the
[installed placement test](../tests/Placement.Tests.ps1) and
[command reference](reference/LibTmux/Move-TmuxWindow.md).
