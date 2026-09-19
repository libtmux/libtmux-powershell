# Remove sessions, windows and panes

`Remove-TmuxSession`, `Remove-TmuxWindow` and `Remove-TmuxPane` accept native
core handles directly or through the pipeline. Each removes its target and
emits no success output. Select the target using the
[explicit endpoint and read commands](read.md).

These commands have high confirmation impact. The default PowerShell
confirmation preference prompts before removal. Review the endpoint and ID
in that prompt; use `-Confirm:$false` when an unattended caller has already
chosen the target. `-WhatIf` describes the removal without contacting tmux:

```powershell
$session | Remove-TmuxSession -WhatIf
```

Remove an owned session after its work finishes:

```powershell
$session | Remove-TmuxSession -Confirm:$false
```

An empty pipeline does nothing. A pipeline with several targets processes
them in input order. A successful removal emits no handles, Boolean values
or task objects, so `@($pane | Remove-TmuxPane -Confirm:$false)` is empty.
Captured fields on an old handle remain an observation of the removed
object; removal does not rewrite that snapshot.

## Linked windows and cascading removal

**Removing a window destroys the physical window, every pane in it, and all
its links in every session.** It does not merely unlink the placement through
which the window was selected. Repeated placements of that physical window
are removed together:

```powershell
$window | Remove-TmuxWindow -Confirm:$false
```

Removing a session destroys windows that are no longer linked elsewhere. A
window still linked to another session survives with its panes.

Removing the last pane destroys its window. Removing the last window from a
session also removes that session; tmux may exit when no sessions remain.
These commands do not give the module ownership of the daemon or arrange
cleanup for other resources.

```powershell
$pane | Remove-TmuxPane -Confirm:$false
```

## Errors and cancellation

Failures retain the native owner and original core exception in the
PowerShell error record. The stable error IDs are `Tmux.SessionRemoveFailed`,
`Tmux.WindowRemoveFailed` and `Tmux.PaneRemoveFailed`. Core exceptions retain
their available dispatch metadata. A missing target remains an error;
`-ErrorAction Continue` permits later pipeline targets to run, while
`-ErrorAction Stop` stops before the next target.

Handles belong to a specific endpoint and daemon generation. The core
rejects an old-generation handle after daemon replacement instead of resolving
the same numeric ID against the replacement. Removal is never retried.
Stopping the pipeline cancels the active client operation; a removal already
accepted by tmux is not rolled back.

The [installed removal test](../tests/Remove.Tests.ps1) checks previews,
zero-output pipelines, per-owner errors, linked-window destruction, session
sharing, last-pane cascades, isolated endpoints and real daemon replacement
on owned tmux servers.
