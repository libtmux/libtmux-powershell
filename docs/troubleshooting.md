# Troubleshooting

Start with the endpoint and operation that failed. The cmdlets keep native
objects and errors, so an empty result, a failed tmux command and a cancelled
wait have different meanings. Use `-ErrorAction Stop` when one failure should
stop a script.

| Symptom | Check and next action |
| --- | --- |
| `Import-Module LibTmux` cannot find a dependency | Use the [source bootstrap](../README.md#install-from-source) for the current shared revision. A direct locked build needs the original unpublished archive directory and `provenance.json` described in [review package builds](../.github/CONTRIBUTING.md#review-package-builds). Importing a mixed or rebuilt same-version core is rejected. |
| A server handle exists, but reads cannot reach tmux | `New-TmuxServer` constructs a local handle. Use [Connect-TmuxServer](read.md) to discover an existing daemon, or [New-TmuxSession](create.md) to create one on that explicit endpoint. Check the selected socket and executable before retrying. |
| A command targets the wrong session or window | Read the object from the intended server and session. [Window placements](placement.md) carry a session-relative index; a physical window can be linked more than once. Raw tmux targets are strings and do not inherit a captured placement guard. |
| A move, input or raw mutation failed after dispatch | Read current topology or screen state before deciding whether to retry. A failed readback or cancelled wait can follow a successful tmux mutation. [Placement](placement.md) and [literal input](input.md) describe the uncertain cases. |
| Sent text has no captured output yet | [Sending text](input.md) acknowledges input, not program completion. Wait on a cooperative channel or a program-specific result, then [capture](capture.md) the pane. A sleep does not establish readiness. |
| A watcher reports dropped events | The [event stream](watch.md) bounds count and text bytes. A loss marker means history is incomplete; acquire a fresh snapshot when current topology matters. Rendered capture is a screen view, not a reconstruction of missed events. |
| Interactive attach fails from a script or CI job | [Enter-TmuxSession](reference/LibTmux/Enter-TmuxSession.md) needs a foreground terminal with stdin and must run outside another tmux client. Workspace apply is detached; pass its successful native `Session` to the attach command in a terminal. |
| Workspace apply stops partway through | Inspect the native `WorkspaceBuildException` journal and partial result described in the [workspace guide](workspace.md#startup-host-effects-and-failures). Review the original plan and live server before another apply; host scripts and sent pane commands are not rolled back. |
| MCP tools or waits are unavailable | The [MCP server](mcp.md) is an independently installed .NET tool. Check the configured executable, socket and `LIBTMUX_TOOLSETS`, then initialize the client and read `tools/list` and `tmux://capabilities`. A cursor or task from an earlier process is not durable. |

For repeatable failures, record the command, PowerShell and tmux versions,
selected socket kind, error ID and original exception. Avoid including pane
contents, secrets or private socket paths in a public report. The
[contributor guide](../.github/CONTRIBUTING.md#testing-tmux-behavior) runs
integration checks on owned sockets without touching your default server.
