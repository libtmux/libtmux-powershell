# Give an assistant tmux tools

Use the separate [LibTmux.Mcp .NET tool](https://www.nuget.org/packages/LibTmux.Mcp)
to let an MCP client inspect panes, wait for output and run commands in tmux.
It uses the same .NET library as libtmux for PowerShell. It does not import
the PowerShell modules or require a PowerShell launcher.

## Install and select a server

Choose an exact published version from NuGet and set `MCP_VERSION` to it.
Install the tool on the Unix host running tmux:

```console
$ dotnet tool install LibTmux.Mcp \
    --tool-path build/mcp \
    --version "$MCP_VERSION"
```

This checkout's unpublished review packages need the original inspected
archives instead; see [MCP development setup](../.github/CONTRIBUTING.md#mcp-discovery).
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

Pane text waits require control observation by default in this checkout's
review tool. Explicitly enabling `LIBTMUX_MCP_ALLOW_POLLING_FALLBACK=true`
allows repeated captures if control observation fails; capabilities disclose
the policy and affected results report `pollingFallback`. Keep finite wait
and output bounds in the request. Inspect `eventsDropped` and truncation
fields before treating observed output as complete.

A `capture_since` cursor tracks observation between calls; it is not a
background job. Progress notifications and optional MCP Tasks are separate
protocol features, available only where the discovered tool declares them.
Read the installed server's schemas and capability rows for those contracts.

## Check discovery from this checkout

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
initializes the installed tool, compares discovery with capabilities, calls
`list_sessions`, and verifies that the result identifies its private `fixture`
session. The suite checks that the session and pane survive MCP shutdown, then
removes the owned fixture. It neither imports the PowerShell modules nor builds,
installs or downloads anything during the test. This is a discovery and
one-tool smoke, not the .NET server's full tool or protocol suite.
