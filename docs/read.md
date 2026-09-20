# Read tmux objects

Create an endpoint with `New-TmuxServer -SocketPath` or `-SocketName`, then
pipe it to a read command. Constructing the endpoint performs no I/O.
`Connect-TmuxServer` discovers an unmaterialized endpoint and returns its
connected replacement. An already connected handle is returned unchanged.

| Command | Typed owner accepted from the pipeline | Output |
| --- | --- | --- |
| `Connect-TmuxServer` | `LibTmux.Server` | `LibTmux.Server` |
| `Get-TmuxSnapshot` | `LibTmux.Server` | Replacement `LibTmux.Server` |
| `Get-TmuxSession` | `LibTmux.Server` | `LibTmux.Session` objects |
| `Get-TmuxWindow` | `LibTmux.Server` or `LibTmux.Session` | `LibTmux.Window` objects |
| `Get-TmuxPane` | `LibTmux.Server`, `LibTmux.Session`, or `LibTmux.Window` | `LibTmux.Pane` objects |

Every `Get-Tmux*` command reads tmux explicitly. `-Id` selects a literal tmux
identifier, such as `$0`, `@1`, or `%2`; use single quotes for a session ID.
Session and window commands also accept `-Name`. Selectors compare ordinally
and distinguish case. They do not expand wildcards. Combining selectors
requires both to match. An unmatched selector emits no objects; it is not an
error. Wrap a pipeline in `@(...)` when its count matters.

Owners bind by their native type. An arbitrary object's `Server`, `Session`,
or `Window` property does not bind automatically. Use `Where-Object` after
acquisition for further local filtering.

`Get-TmuxSnapshot` defaults to `-Depth Panes`. Shallower depths are `Server`,
`Sessions`, and `Windows`. It returns a replacement graph and leaves the
input handle and earlier snapshots unchanged. `SnapshotMetadata` records the
depth, daemon generation, UTC start/end readings and monotonic `Elapsed` time.
UTC can move backwards if the clock is adjusted; use `Elapsed` for duration.
Even `-Depth Server` performs a fresh generation-guarded read.

Snapshot acquisition spans several tmux commands; it does not promise an
atomic view. Contradictory parent, child-count or active-child observations
fail with `InconsistentSnapshotException` and emit no graph. Equal-count
changes can escape detection. The command never retries automatically. Uncaptured
relations report `IsCaptured = false` and throw when enumerated. Property
access never reads tmux. Captured panes expose `CurrentCommand` and
`CurrentPath`, which remain readable after the daemon exits. A field that was
not captured raises `IncompleteSnapshotException`; a captured empty string
or null retains that value.

Captured children retain their root through `Server`. Parent and active-child
properties return the captured instances when that depth is available. A pane's
`Window` retains its session/index placement, including repeated links to the
same window. `Window.LinkedSessions` contains each related session once.
Filtering a collection changes only selected membership; traversing its
parents still reaches their complete captured children. Active properties use
the IDs from their own parent's row, so separate reads can record different
selection states.

`Update-TmuxPane` refreshes one pane's fields. Its parent navigation does not
borrow captured data from an older graph, even when its `Server` names an older
captured root. Acquire another snapshot for a new graph.

Default tables show native identifiers, captured names or titles, and owner
context. Handles resolved only by identifier show blank columns for fields
they have not captured. The views distinguish that specific missing-field
condition from other failures. Formatting and `Get-Member` use local data and
remain usable after the daemon exits. They do not refresh objects.

Read failures write an error for the affected owner, including an endpoint
with no running server, then allow later pipeline owners to continue.
Use `-ErrorAction Stop` to terminate instead. Error IDs are
`Tmux.ConnectFailed`, `Tmux.SnapshotFailed`,
`Tmux.SessionReadFailed`, `Tmux.WindowReadFailed`, and `Tmux.PaneReadFailed`.
The error record retains the core exception and its dispatch metadata when
the exception supplies it. Pipeline cancellation cancels the pending core
operation; borrowed server handles do not own daemon lifetime.

The [installed-module integration test](../tests/Read.Tests.ps1) executes
typed pipelines, exact selection, shallow and replacement snapshots, and
strict errors against its own tmux server. The fixture owns teardown.
The [snapshot integration test](../tests/Snapshot.Tests.ps1) checks provenance,
repeated placements, parent navigation after teardown and contradictory reads.
The [formatting integration test](../tests/Formatting.Tests.ps1) checks
captured objects and identity-only handles after daemon shutdown, including
that formatting and member discovery start no tmux processes.
