# Give an assistant tmux tools

Use the separate [LibTmux.Mcp .NET tool](https://www.nuget.org/packages/LibTmux.Mcp)
to let an MCP client inspect panes, wait for output and run commands in tmux.
It uses the same .NET library as libtmux for PowerShell. It does not import
the PowerShell modules or require a PowerShell launcher.

## Install and select a server

Install the published alpha.20 tool on the Unix host running tmux:

```console
$ dotnet tool install LibTmux.Mcp \
    --tool-path build/mcp \
    --version 0.0.0-alpha.20 \
    --framework net8.0
```

For shared .NET source changes, use the optional
[MCP development setup](../.github/CONTRIBUTING.md#mcp-discovery).
A desktop-launched client may need `DOTNET_ROOT` in its server environment
when .NET comes from a version manager.

For clients using an `mcpServers` configuration, replace these absolute paths
with the installed tool, tmux executable and an existing server socket:

```json
{
  "mcpServers": {
    "tmux": {
      "command": "/absolute/tool-directory/libtmux-mcp",
      "env": {
        "LIBTMUX_TMUX": "/absolute/path/to/tmux",
        "LIBTMUX_SOCKET_PATH": "/absolute/path/to/tmux/socket",
        "LIBTMUX_TOOLSETS": "inspect"
      }
    }
  }
}
```

Other clients use different configuration formats; see the
[.NET MCP client setup](https://libtmux.org/en/dotnet/latest/mcp/#install).
Launch the executable directly: standard input and output carry MCP messages.

Use `LIBTMUX_SOCKET` for a socket name or `LIBTMUX_SOCKET_PATH` for an absolute
path. Set only one, including inherited environment variables. The choice is
fixed at startup; calls cannot switch sockets. Shut down the client connection
when finished. The server leaves a borrowed tmux daemon running.

## Discover before calling

After initialization, read the server instructions, call `tools/list`, and
read `tmux://capabilities`. The resource identifies the selected socket,
effective tools and observation policy. Tool discovery supplies schemas,
descriptions and annotations. Each advertised tool also carries its capability row in
`_meta["com.git-pull.libtmux-mcp/capability"]`.

The example selects `inspect`. Add `manage`, `execute` or `teardown` only for
the operations your client needs, then restart it to change the selection.
Toolsets shape the interface; they are not an authorization boundary. Commands
execute with the tmux user's authority.

| Task | Start with |
| --- | --- |
| Find a session, window or pane | `list_sessions`, `list_windows`, `list_panes` |
| Read terminal text | `capture_pane`; `snapshot_pane` for structured state |
| Find text across panes | `search_panes` |
| Wait for text that has not appeared | `wait_for_text` with a finite timeout |
| Read changes across later calls | `capture_since`, retaining its returned cursor |
| Run your own command and observe its completion | `run_shell_command` from the `execute` toolset |
| Combine independent reads in one request | `call_read_tools_batch`; its operations run serially |

Input acknowledgement does not prove a shell command finished. Use the
completion result of `run_shell_command` for a command you start; cancellation
or timeout can leave that command running in its pane. For a program already
running, wait for its output rather than repeatedly capturing the screen.

Pane text waits require control observation by default in alpha.20.
Explicitly enabling `LIBTMUX_MCP_ALLOW_POLLING_FALLBACK=true`
allows repeated captures if control observation fails; capabilities disclose
the policy and affected results report `pollingFallback`. Give text waits a
finite timeout; the server bounds their returned tail. For captures, select
`maxLines`. Inspect `eventsDropped` and truncation fields before treating
observed output as complete.

A `capture_since` cursor tracks observation between calls; it is not a
background job. Progress notifications and optional MCP Tasks are separate
protocol features, available only where the discovered tool declares them.
Read the installed server's schemas and capability rows for those contracts.

## Inspect a pane and wait for readiness

After discovery, select a session from `list_sessions`. These are `tools/call`
parameter objects: replace `$0` and `%0` with IDs returned by your server.
The inspect toolset includes all three calls.

List the selected session's panes:

<!-- mcp-example: list_panes -->
```json
{
  "name": "list_panes",
  "arguments": { "session": "$0" }
}
```

The response's `structuredContent.result` contains pane records with
`paneId`, `windowId`, `sessionId`, dimensions and the current command. Select
one pane and read its rendered screen:

<!-- mcp-example: capture_pane -->
```json
{
  "name": "capture_pane",
  "arguments": { "paneId": "%0", "maxLines": 64 }
}
```

For this object result, read `structuredContent.content.lines` directly.
`content.truncated`, `content.droppedLines` and `content.droppedBytes` disclose
output omitted to fit the budget. A list result has the `result` wrapper;
object results do not. Check `isError` before interpreting either shape.

If the application prints `Service ready`, wait for that whole line:

<!-- mcp-example: wait_for_text -->
```json
{
  "name": "wait_for_text",
  "arguments": {
    "paneId": "%0",
    "patterns": ["^Service ready$"],
    "timeoutSeconds": 1,
    "ignoreCase": false
  }
}
```

An existing line returns `structuredContent.outcome = "PresentAtEntry"`;
a later line returns `"Matched"`. `matchedPattern` identifies the condition,
and `tail` contains bounded rendered text. Stop-pattern, timeout and pane-death
outcomes remain distinct. A ready-line match is an application-specific
condition; it does not establish shell exit status or continuing health.

The [official SDK client](../tests/support/McpDiscovery/Program.cs) reads these
three request examples, substitutes discovered IDs and executes them against
an installed tool. Its owned fixture prints the ready line before the calls,
then checks capture, `PresentAtEntry`, an untruncated tail, no polling or event
drops, stdio shutdown and preservation of the borrowed tmux state.

Use a finite server timeout even when your client can cancel. With the pinned
SDK 2.2.0, cancelling a local token does not reliably send
`notifications/cancelled`; it can leave the remote wait running until its
timeout. A client that knows its request ID can explicitly send that
notification. For negotiated MCP Tasks, cancel the task with `tasks/cancel`
using its returned task ID. Neither cancellation stops the application in
the pane. Task records are temporary and disappear on expiry or restart.

## Check the client workflow from this checkout

After [building the discovery probe](../.github/CONTRIBUTING.md#mcp-discovery),
set `MCP_COMMAND` to the installed executable's absolute path and
`MCP_VERSION` to its exact version. Select the desired tmux on `PATH`, then run:

```console
$ pwsh -NoLogo -NoProfile -File eng/Test.ps1 \
    -Suite Mcp \
    -McpCommand "$MCP_COMMAND" \
    -McpVersion "$MCP_VERSION"
```

The [official SDK client source](../tests/support/McpDiscovery/Program.cs)
initializes the installed tool, compares discovery with capabilities, then
executes `list_sessions` and the three request examples above. The suite
checks that the session and pane survive MCP shutdown, then removes the owned
fixture. It neither imports the PowerShell modules nor builds, installs or
downloads anything during the test. Broader task, cancellation, loss and
concurrent-wait acceptance belongs to the .NET protocol suite.
