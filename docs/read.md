# Read tmux objects

The cmdlets return native objects from
[libtmux for .NET](https://github.com/libtmux/libtmux-dotnet). Inspect them
with `Get-Member`, select their properties and pass them to other cmdlets.

## Choose a server

Create an endpoint with `New-TmuxServer -SocketPath` or `-SocketName`, then
pipe it to a read command. Creating it does no I/O.

- **No socket parameter:** tmux picks the server: the one `TMUX` names inside a
  tmux pane, otherwise its default socket.
- **Environment:** `LIBTMUX_SOCKET_PATH` (`-S`) or `LIBTMUX_SOCKET` (`-L`)
  chooses a socket for such an endpoint, the path first. A blank value counts
  as unset, and a parameter beats both. The endpoint reads them when it is made.
- **`Connect-TmuxServer`:** discovers an unmaterialized endpoint and returns its
  connected replacement. A connected handle is returned unchanged.

| Command | Typed owner accepted from the pipeline | Output |
| --- | --- | --- |
| `Connect-TmuxServer` | `LibTmux.Server` | `LibTmux.Server` |
| `Get-TmuxSnapshot` | `LibTmux.Server` | Replacement `LibTmux.Server` |
| `Get-TmuxSession` | `LibTmux.Server` | `LibTmux.Session` objects |
| `Get-TmuxWindow` | `LibTmux.Server` or `LibTmux.Session` | `LibTmux.Window` objects |
| `Get-TmuxPane` | `LibTmux.Server`, `LibTmux.Session`, or `LibTmux.Window` | `LibTmux.Pane` objects |

These commands read tmux explicitly.

## Select objects

- **`-Id`** selects a literal tmux identifier, such as `$0`, `@1` or `%2`. Use
  single quotes for a session ID.
- **`-Name`** is also accepted by session and window commands.
- Selectors compare ordinally and distinguish case. They do not expand
  wildcards, and combined selectors must all match.
- An unmatched selector emits no objects and is not an error. Wrap a pipeline
  in `@(...)` when its count matters.
- Owners bind by their native type. Property names on another object do not
  bind from the pipeline.
- Tab completion for `-Name` and `-Id` offers values from a captured server,
  session or window, never from tmux. Capture first with `Get-TmuxSnapshot`; an
  uncaptured owner offers none. The command still checks current state when you
  run it.

For more filtering, use `Where-Object` after acquisition. For reusable
criteria, use [New-TmuxQuery](reference/LibTmux/New-TmuxQuery.md) with the local
[Select-TmuxPane](reference/LibTmux/Select-TmuxPane.md),
[Select-TmuxWindow](reference/LibTmux/Select-TmuxWindow.md) or
[Select-TmuxSession](reference/LibTmux/Select-TmuxSession.md).
[Get-TmuxQueryField](reference/LibTmux/Get-TmuxQueryField.md) lists the fields.

For a fresh query, pass an endpoint and a query document to
[Invoke-TmuxQuery](reference/LibTmux/Invoke-TmuxQuery.md). It emits matching
native objects; `-AsResult` keeps the result and its complete captured graph,
including an empty selection.
[Get-TmuxQueryPlan](reference/LibTmux/Get-TmuxQueryPlan.md) shows source
evaluation, local residuals and fallback reasons before execution, with no I/O.
The [query guide](query.md) has the details.

## Snapshots

`Get-TmuxSnapshot` defaults to `-Depth Panes`. Shallower depths are
[`Server`][snapshotdepth-server], [`Sessions`][snapshotdepth-sessions], and
[`Windows`][snapshotdepth-windows]. It returns a replacement graph and leaves
the input handle and earlier snapshots unchanged. Even `-Depth Server` performs
a fresh, generation-guarded read.

- **Metadata:** `SnapshotMetadata` records the depth, daemon generation, UTC
  start and end readings, and monotonic [`Elapsed`][snapshotmetadata-elapsed]
  time. UTC can move backwards if the clock is adjusted; use `Elapsed` for
  duration.
- **Not atomic:** a snapshot spans several tmux commands. Contradictory parent,
  child-count or active-child observations fail with
  `InconsistentSnapshotException` and emit no graph. Equal-count changes can
  escape detection. The command never retries.
- **Uncaptured data:** uncaptured relations report `IsCaptured = false` and
  throw when enumerated. A field that was not captured raises
  `IncompleteSnapshotException`; a captured empty string or null keeps its
  value. Property access never reads tmux.
- **After the daemon exits:** captured panes expose `CurrentCommand` and
  `CurrentPath`, and formatting and `Get-Member` keep working. They do not
  refresh objects.

## Navigate a captured graph

- **Parents:** captured children keep their root through `Server`, and parent
  properties return the captured instances when that depth is available.
- **Placement:** a pane's `Window` keeps its session and index placement,
  including repeated links to the same window. `Window.LinkedSessions` lists
  each related session once.
- **Active children:** `Session.ActiveWindow`,
  [`Session.ActivePane`][session-activepane] and
  [`Window.ActivePane`][window-activepane] return `CapturedValue<T>`. Check
  [`IsCaptured`][capturedvalue-iscaptured], then read
  [`Value`][capturedvalue-value]. Reading an unavailable `Value` raises
  `IncompleteSnapshotException`; `OrNull()` returns null instead. Active
  properties use the IDs from their own parent's row, so separate reads can
  record different selections.
- **Filtering:** filtering a collection changes only which items are selected.
  Traversing their parents still reaches the complete captured children.
- **Refresh:** `Update-TmuxPane` refreshes one pane's fields. Its parent
  navigation does not borrow data from an older graph. Take another snapshot for
  a new graph.

Default tables show native identifiers, captured names or titles, and owner
context. A handle resolved only by identifier shows blank columns for fields it
has not captured, and the views tell that apart from other failures.

## Errors

A read failure writes an error for the affected owner, including an endpoint
with no running server, and later owners in the pipeline continue. Use
`-ErrorAction Stop` to terminate instead.

Error IDs are [`Tmux.ConnectFailed`][connecttmuxservercommand],
[`Tmux.SnapshotFailed`][gettmuxsnapshotcommand],
[`Tmux.SessionReadFailed`][gettmuxsessioncommand],
[`Tmux.WindowReadFailed`][gettmuxwindowcommand] and
[`Tmux.PaneReadFailed`][gettmuxpanecommand]. The error record keeps the core
exception and its dispatch metadata when it has them. Cancelling the pipeline
cancels the pending core operation, and borrowed server handles do not own the
daemon's lifetime.

[snapshotdepth-sessions]: https://libtmux.org/en/csharp/latest/reference/libtmux-snapshotdepth-sessions/
[snapshotdepth-windows]: https://libtmux.org/en/csharp/latest/reference/libtmux-snapshotdepth-windows/
[snapshotmetadata-elapsed]: https://libtmux.org/en/csharp/latest/reference/libtmux-snapshotmetadata-elapsed/
[capturedvalue-iscaptured]: https://libtmux.org/en/csharp/latest/reference/libtmux-capturedvalue-iscaptured/
[capturedvalue-value]: https://libtmux.org/en/csharp/latest/reference/libtmux-capturedvalue-value/
[connecttmuxservercommand]: ../src/LibTmux.PowerShell/ConnectTmuxServerCommand.cs
[gettmuxsnapshotcommand]: ../src/LibTmux.PowerShell/GetTmuxSnapshotCommand.cs
[gettmuxsessioncommand]: ../src/LibTmux.PowerShell/GetTmuxSessionCommand.cs
[gettmuxwindowcommand]: ../src/LibTmux.PowerShell/GetTmuxWindowCommand.cs
[gettmuxpanecommand]: ../src/LibTmux.PowerShell/GetTmuxPaneCommand.cs

[snapshotdepth-server]: https://libtmux.org/en/csharp/latest/reference/libtmux-snapshotdepth-server/
[session-activepane]: https://libtmux.org/en/csharp/latest/reference/libtmux-session-activepane/
[window-activepane]: https://libtmux.org/en/csharp/latest/reference/libtmux-window-activepane/
