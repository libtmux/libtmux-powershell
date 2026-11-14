# Remove sessions, windows and panes

`Remove-TmuxSession`, `Remove-TmuxWindow` and `Remove-TmuxPane` take handles
directly or from the pipeline. Each removes its target and emits nothing on
success. Choose the target with the [explicit endpoint and read commands](read.md).

Removal has high confirmation impact, so the default preference prompts. Check
the endpoint and ID in the prompt, and use `-Confirm:$false` when an unattended
caller has already chosen the target. `-WhatIf` describes the removal without
contacting tmux:

<!-- example: remove.preview -->
```powershell
$session | Remove-TmuxSession -WhatIf
```

Remove an owned session after its work finishes:

<!-- example: remove.session -->
```powershell
$session | Remove-TmuxSession -Confirm:$false
```

- An empty pipeline does nothing, and several targets are processed in input
  order.
- Success emits no handles, Booleans or task objects, so
  `@($pane | Remove-TmuxPane -Confirm:$false)` is empty.
- An old handle keeps its captured fields as an observation of the removed
  object.

## Linked windows and cascading removal

**Removing a window destroys the physical window, every pane in it, and all
its links in every session.** It does not merely unlink the placement through
which the window was selected. Repeated placements of that physical window
are removed together:

<!-- example: remove.window -->
```powershell
$window | Remove-TmuxWindow -Confirm:$false
```

To remove one session placement while preserving other links, use
[Remove-TmuxWindowLink](placement.md).

- Removing a session destroys windows linked nowhere else. A window still linked
  to another session survives with its panes.
- Removing the last pane destroys its window. Removing a session's last window
  removes the session, and tmux may exit when no sessions remain.
- None of this gives the module ownership of the daemon or cleans up other
  resources.

<!-- example: remove.pane -->
```powershell
$pane | Remove-TmuxPane -Confirm:$false
```

## Errors and cancellation

- **Error IDs:** [`Tmux.SessionRemoveFailed`][removetmuxsessioncommand],
  [`Tmux.WindowRemoveFailed`][removetmuxwindowcommand] and
  [`Tmux.PaneRemoveFailed`][removetmuxpanecommand]. The error record keeps the
  native owner, the original core exception and its dispatch metadata.
- **Missing target:** an error. `-ErrorAction Continue` lets later targets run,
  and `-ErrorAction Stop` stops before the next one.
- **Stale handles:** a handle belongs to one endpoint and daemon generation. After
  the daemon is replaced, the core rejects an old handle instead of resolving
  its numeric ID against the replacement.
- **Retries and cancellation:** removal is never retried. Stopping the pipeline
  cancels the active client operation; a removal tmux already accepted is not
  rolled back.

[removetmuxsessioncommand]: ../src/LibTmux.PowerShell/RemoveTmuxSessionCommand.cs
[removetmuxwindowcommand]: ../src/LibTmux.PowerShell/RemoveTmuxWindowCommand.cs
[removetmuxpanecommand]: ../src/LibTmux.PowerShell/RemoveTmuxPaneCommand.cs
