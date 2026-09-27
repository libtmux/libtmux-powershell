# libtmux for PowerShell

Drive [tmux](https://github.com/tmux/tmux) with native PowerShell cmdlets.
Create sessions, arrange panes, send input and capture terminal output.
Read state once, then work with typed objects through ordinary pipelines.

Built on [libtmux for .NET](https://github.com/libtmux/libtmux-dotnet), in the
same [libtmux organization](https://github.com/libtmux) and with the same main
author. The cmdlets return its native objects and add PowerShell parameter
binding, help, formatting and `-WhatIf` / `-Confirm`.

[Quick start](#quick-start) · [Install](#install-from-source) ·
[Execution modes](#choose-how-to-run) · [Guides](#guides) ·
[Compatibility](docs/compatibility.md) ·
[Troubleshooting](docs/troubleshooting.md) ·
[Cmdlet reference](docs/reference/LibTmux)

**Alpha.** APIs may change. Build from this checkout; the modules are not yet
published to PowerShell Gallery.

## Quick start

After [building the modules](#install-from-source), choose an explicit socket.
`New-TmuxServer` creates a handle; it does not start or contact tmux.

<!-- example: read.endpoint -->
```powershell
$server = LibTmux\New-TmuxServer -SocketName development
```

Create two panes, capture their state, then remove the session. `cat` keeps
the panes open without shell configuration. An existing `demo` session causes
an error.

<!-- example: readme.create -->
```powershell
$captured = & {
    $ErrorActionPreference = 'Stop'
    $session = $server | New-TmuxSession -Name demo -Command 'exec /bin/cat' -Width 100 -Height 30
    try {
        $pane = $session | Get-TmuxPane
        $null = $pane | Split-TmuxPane -Horizontal -Size 40 -Command 'exec /bin/cat'
        ($server | Get-TmuxSnapshot).Sessions | Where-Object Name -CEQ demo
    } finally {
        $session | Remove-TmuxSession -Confirm:$false
    }
}
```

`$captured` is a native `LibTmux.Session` with one window and two panes.
The snapshot remains readable after cleanup; other sessions are left alone.
Filter its panes with an ordinary PowerShell pipeline:

<!-- example: readme.filter -->
```powershell
$captured.Panes | Where-Object Width -GE 50 | Select-Object Id, Width, Height
```

The result is the wider pane: 59 columns by 30 rows. Filtering and property
access use captured data; `Get-TmuxSnapshot` explicitly reads fresh state.
See [reading and filtering](docs/read.md) for IDs, arrays and linked windows.

## Choose how to run

| Task | Use | Example |
| --- | --- | --- |
| Read or change tmux state | Typed cmdlets and pipelines | [Create sessions and panes](docs/create.md) |
| Enter a session interactively | `Enter-TmuxSession` | [Attach your foreground terminal](docs/reference/LibTmux/Enter-TmuxSession.md) |
| Run an ordered batch | `New-TmuxCommand` → `Invoke-TmuxChain` | [Compose commands](docs/commands.md) |
| Reuse a connected client | `Connect-TmuxControl` → `Invoke-TmuxControlCommand` | [Control commands and cleanup](docs/commands.md) |
| React to output and notifications | `Watch-TmuxEvent` | [Bounded event streams](docs/watch.md) |
| Keep the prompt available | `Start-ThreadJob` | [Bounded background jobs](docs/watch.md#bound-background-output) |
| Run commands concurrently | `ForEach-Object -Parallel` | [Independent clients](docs/watch.md#run-independent-commands-concurrently) |

Foreground cmdlets occupy their pipeline until they finish. Jobs and worker
runspaces provide concurrency; control mode keeps a client connected for
repeated commands. Watchers accept event-count and text-byte limits.

Sending text acknowledges input, not completion of the receiving program.
The [send, wait and capture example](docs/input.md#send-a-command-and-wait-for-its-output)
uses a unique tmux channel to capture output after the shell signals completion.

## Modules and MCP

| Product | Use it for |
| --- | --- |
| [LibTmux](docs/reference/LibTmux) | Typed cmdlets, snapshots, input, capture, control clients and event streams |
| [LibTmux.Workspace](docs/workspace.md) | Discover YAML/JSON declarations, resolve directories, review plans and create workspaces |
| [LibTmux.Mcp](docs/mcp.md) | Giving an assistant tmux tools through the separately installed .NET MCP server |

The workspace module parses YAML into a native
`LibTmux.Workspace.WorkspaceFile` without running its commands:

<!-- example: workspace.parse -->
```powershell
LibTmux.Workspace\Import-TmuxWorkspace -Yaml 'session_name: development'
```

To build a usable workspace, follow the
[declaration and planning guide](docs/workspace.md): define windows and panes,
inspect the plan, preview it with `-WhatIf`, then apply that exact plan.

Install both PowerShell modules at the same version. The MCP server is an
independent .NET tool and does not require PowerShell.

## Install from source

Use PowerShell 7.4 or later with tmux on Linux x64. macOS is under test.
Install the pinned development tools from the repository root:

```console
$ mise install
```

This checkout pins unpublished .NET review packages. If you have the original
inspected archives and their `provenance.json`, set `CORE_PACKAGES` to that
directory and build with the existing lockfiles:

```console
$ pwsh -NoLogo -NoProfile -File eng/Build.ps1 \
    -Restore \
    -CorePackageDirectory "$CORE_PACKAGES"
```

To build the dependencies yourself, follow the
[review package recipe](.github/CONTRIBUTING.md#review-package-builds). Use a
new package version and update the exact pins and lockfiles as described there;
rebuilding the source does not reproduce the original locked archives.

Open PowerShell with the built modules on its search path:

```console
$ PSModulePath="$PWD/build/Modules" pwsh -NoLogo -NoProfile
```

See [contributing](.github/CONTRIBUTING.md) for local packages and development
checks. Run the examples in that PowerShell session.

## Guides

- **Read:** [snapshots and filtering](docs/read.md), [structured queries](docs/query.md),
  [pane contents and scrollback](docs/capture.md), [attached clients](docs/clients.md).
- **Automate:** [create](docs/create.md), [send text and keys](docs/input.md),
  [arrange and resize](docs/layout.md), [link and move windows](docs/placement.md),
  [remove](docs/remove.md).
- **Configure:** [options](docs/options.md), [hooks](docs/hooks.md),
  [environment for new panes](docs/environment.md).
- **Coordinate:** [chains and control clients](docs/commands.md),
  [event streams, jobs and parallel workers](docs/watch.md).
- **Assistants:** [install and configure the MCP server](docs/mcp.md).
- **Workspaces:** [load, review and apply](docs/workspace.md),
  [export a starting declaration](docs/workspace.md#export-a-starting-declaration),
  [edit a declaration](docs/workspace.md#edit-the-declaration).

Examples are shared with the [executable guides](examples/Guides.ps1) and run
against real tmux through the installed modules. See
[contributing](.github/CONTRIBUTING.md) for the example runner and development
checks.

The [benchmarks](benchmarks/README.md) compare pane enumeration, command
dispatch and linked-pane query selection, and measure event loss under queue
pressure. They use owned servers and record raw samples with package
provenance.
