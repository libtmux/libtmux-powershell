# Read tmux objects

The cmdlets return native objects from
[libtmux for .NET](https://github.com/libtmux/libtmux-dotnet). Inspect them with
`Get-Member`, select their properties and pass them directly to other cmdlets.

Create an endpoint with `New-TmuxServer -SocketPath` or `-SocketName`, then
pipe it to a read command. Constructing the endpoint performs no I/O.

With neither parameter the endpoint passes tmux no socket, and tmux picks the
server: the one `TMUX` names inside a tmux pane, otherwise its default socket.
`LIBTMUX_SOCKET_PATH` (`-S`) or `LIBTMUX_SOCKET` (`-L`) chooses a socket for
such an endpoint instead, the path first; a blank value counts as unset, and a
parameter beats both. The endpoint reads the variables when it is made.

`Connect-TmuxServer` discovers an unmaterialized endpoint and returns its
connected replacement. An already connected handle is returned unchanged.

| Command | Typed owner accepted from the pipeline | Output |
| --- | --- | --- |
| `Connect-TmuxServer` | `LibTmux.Server` | `LibTmux.Server` |
| `Get-TmuxSnapshot` | `LibTmux.Server` | Replacement `LibTmux.Server` |
| `Get-TmuxSession` | `LibTmux.Server` | `LibTmux.Session` objects |
| `Get-TmuxWindow` | `LibTmux.Server` or `LibTmux.Session` | `LibTmux.Window` objects |
| `Get-TmuxPane` | `LibTmux.Server`, `LibTmux.Session`, or `LibTmux.Window` | `LibTmux.Pane` objects |

The acquisition commands above read tmux explicitly. `-Id` selects a literal tmux
identifier, such as `$0`, `@1`, or `%2`; use single quotes for a session ID.
Session and window commands also accept `-Name`. Selectors compare ordinally
and distinguish case. They do not expand wildcards. Combining selectors
requires both to match. An unmatched selector emits no objects; it is not an
error. Wrap a pipeline in `@(...)` when its count matters.

For `-Name` and `-Id`, Tab offers values from an explicitly supplied captured
server, session or window. Capture first with `Get-TmuxSnapshot`. Completion
does not contact tmux, refresh a handle or guess an endpoint. An uncaptured
owner offers no tmux values. The suggestion comes from the earlier observation;
the read command still checks current tmux state when you run it.

Owners bind by their native type. Property names on an arbitrary object do
not provide pipeline binding. Use `Where-Object` after
acquisition for further local filtering. For reusable criteria, use
[New-TmuxQuery](reference/LibTmux/New-TmuxQuery.md) and the local
[Select-TmuxPane](reference/LibTmux/Select-TmuxPane.md),
[Select-TmuxWindow](reference/LibTmux/Select-TmuxWindow.md) or
[Select-TmuxSession](reference/LibTmux/Select-TmuxSession.md) commands.
[Get-TmuxQueryField](reference/LibTmux/Get-TmuxQueryField.md) discovers the
shared query catalog locally.

For a fresh query, pass an explicit endpoint and a query document to
[Invoke-TmuxQuery](reference/LibTmux/Invoke-TmuxQuery.md). It emits matching
native objects; `-AsResult` retains the result and its complete captured graph,
including an empty selection. Use
[Get-TmuxQueryPlan](reference/LibTmux/Get-TmuxQueryPlan.md) with a known daemon
version to inspect source evaluation, local residuals and fallback reasons
before execution. Planning performs no I/O. The [query guide](query.md) walks
through native filtering, reusable criteria, relationships and source plans.

`Get-TmuxSnapshot` defaults to `-Depth Panes`. Shallower depths are
[`Server`][snapshotdepth-server], [`Sessions`][snapshotdepth-sessions], and
[`Windows`][snapshotdepth-windows]. It returns a replacement graph and leaves
the input handle and earlier snapshots unchanged. `SnapshotMetadata` records the
depth, daemon generation, UTC start/end readings and monotonic
[`Elapsed`][snapshotmetadata-elapsed] time. UTC can move backwards if the clock
is adjusted; use [`Elapsed`][snapshotmetadata-elapsed] for duration. Even
`-Depth Server` performs a fresh generation-guarded read.

Snapshot acquisition spans several tmux commands; it does not promise an
atomic view. Contradictory parent, child-count or active-child observations
fail with `InconsistentSnapshotException` and emit no graph. Equal-count
changes can escape detection. The command never retries automatically. Uncaptured
relations report `IsCaptured = false` and throw when enumerated. Property
access never reads tmux. Captured panes expose `CurrentCommand` and
`CurrentPath`, which remain readable after the daemon exits. A field that was
not captured raises `IncompleteSnapshotException`; a captured empty string
or null retains that value.

Captured children retain their root through `Server`. Parent properties return
the captured instances when that depth is available. `Session.ActiveWindow`,
[`Session.ActivePane`][session-activepane] and
[`Window.ActivePane`][window-activepane] return `CapturedValue<T>`: inspect
[`IsCaptured`][capturedvalue-iscaptured], then read
[`Value`][capturedvalue-value] for the captured object. Reading an unavailable
[`Value`][capturedvalue-value] raises `IncompleteSnapshotException`; `OrNull()`
explicitly opts into null instead. A pane's `Window` retains its session/index
placement, including repeated links to the same window. `Window.LinkedSessions`
contains each related session once. Filtering a collection changes only selected
membership; traversing its parents still reaches their complete captured
children. Active properties use the IDs from their own parent's row, so separate
reads can record different selection states.

`Update-TmuxPane` refreshes one pane's fields. Its parent navigation does not
borrow captured data from an older graph, even when its `Server` names an older
captured root. Acquire another snapshot for a new graph.

Default tables show native identifiers, captured names or titles, and owner
context. Handles resolved only by identifier show blank columns for fields
they have not captured. The views distinguish that specific missing-field
condition from other failures. Formatting and `Get-Member` use local data and
remain usable after the daemon exits. They do not refresh objects.

Read failures write an error for the affected owner, including an endpoint with
no running server, then allow later pipeline owners to continue. Use
`-ErrorAction Stop` to terminate instead. Error IDs are
[`Tmux.ConnectFailed`][connecttmuxservercommand],
[`Tmux.SnapshotFailed`][gettmuxsnapshotcommand],
[`Tmux.SessionReadFailed`][gettmuxsessioncommand],
[`Tmux.WindowReadFailed`][gettmuxwindowcommand], and
[`Tmux.PaneReadFailed`][gettmuxpanecommand]. The error record retains the core
exception and its dispatch metadata when the exception supplies it. Pipeline
cancellation cancels the pending core operation; borrowed server handles do not
own daemon lifetime.

The [installed-module integration test](../tests/Read.Tests.ps1) executes
typed pipelines, exact selection, shallow and replacement snapshots, and
strict errors against its own tmux server. The fixture owns teardown.
The [snapshot integration test](../tests/Snapshot.Tests.ps1) checks provenance,
repeated placements, parent navigation after teardown and contradictory reads.
The [formatting integration test](../tests/Formatting.Tests.ps1) checks
captured objects and identity-only handles after daemon shutdown, including
that formatting and member discovery start no tmux processes.
The [completion integration test](../tests/Completion.Tests.ps1) checks Tab
suggestions after teardown and verifies that completion starts no tmux client.

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
