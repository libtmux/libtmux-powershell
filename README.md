# libtmux for PowerShell

Drive [tmux](https://github.com/tmux/tmux) from PowerShell. Create sessions,
arrange panes, send input, and read terminal output through native cmdlets.
Snapshots return typed objects that you can traverse and filter with ordinary
PowerShell pipelines.

Built on [libtmux for .NET](https://github.com/libtmux/libtmux-dotnet), in the
same [libtmux organization](https://github.com/libtmux) and with the same main
author. The cmdlets return its native objects and add PowerShell parameter
binding, help, formatting and `-WhatIf` / `-Confirm`.

[Install](#install-from-source) · [Object graph](#create-and-read-an-object-graph) ·
[Send and capture](#send-a-command-and-capture-its-output) ·
[Execution modes](#choose-how-to-run) · [Guides](#guides) ·
[Compatibility](docs/compatibility.md) ·
[Troubleshooting](docs/troubleshooting.md) ·
[Cmdlet reference](docs/reference/README.md)

**Alpha.** APIs may change. Build from this checkout; the modules are not yet
published to PowerShell Gallery.

## Install from source

This checkout targets PowerShell 7.4 and .NET 8. Run PowerShell and tmux on the
same Unix host; see [compatibility](docs/compatibility.md) for tested versions.
Install the tools pinned by [.tool-versions](.tool-versions):

```console
$ mise install
```

Install tmux with your operating system's package manager and check that it
is on `PATH`:

```console
$ tmux -V
```

The branch pins unpublished .NET review packages. To use its existing
lockfiles, set `CORE_PACKAGES` to a directory containing the exact inspected
archives and `provenance.json`, then build both PowerShell modules:

```console
$ pwsh -NoLogo -NoProfile -File eng/Build.ps1 \
    -Restore \
    -CorePackageDirectory "$CORE_PACKAGES"
```

If you do not have those archives, follow the
[review-package source recipe](.github/CONTRIBUTING.md#review-package-builds).
It builds the linked [.NET core](https://github.com/libtmux/libtmux-dotnet),
chooses a new package version, and updates the exact pins and lockfiles. The
review build is local; it does not publish packages.

Start PowerShell with the staged modules on its search path:

```console
$ PSModulePath="$PWD/build/Modules" pwsh -NoLogo -NoProfile
```

The commands below run in that PowerShell session. The workspace module is
installed alongside the core module; the MCP server is a separate .NET tool.
Use `Get-Command -Module LibTmux` to browse cmdlets and
`Get-Help LibTmux\New-TmuxSession -Examples` for installed examples.

Run the [quick start](examples/QuickStart.ps1) from the checkout root. It
creates a private server, splits the `editor` window, adds `logs`, and returns
a captured native `LibTmux.Session`. Show each window's pane IDs:

<!-- example: readme.quickstart -->
```powershell
(./examples/QuickStart.ps1).Windows |
    Select-Object Name, @{ Name = 'PaneIds'; Expression = { $_.Panes.Id -join ', ' } }
```

Output from the private server:

```text
Name   PaneIds
----   -------
editor %0, %1
logs   %2
```

Assign `./examples/QuickStart.ps1` to a variable to keep the session object.
Its `Windows` and `Panes` remain readable after the script removes its session.
The script uses a unique socket and leaves your default tmux server alone.

## Create and read an object graph

Choose a unique socket and a clean tmux configuration. `New-TmuxServer`
creates a handle without contacting tmux. The example does not touch your
default server.

<!-- example: read.endpoint -->
```powershell
$server = LibTmux\New-TmuxServer `
    -SocketName ('libtmux-readme-' + [Guid]::NewGuid().ToString('N')) `
    -ConfigurationFile /dev/null
```

Create a session with an editor window, split it, add a logs window, and take
one snapshot. `cat` keeps the three panes open without shell setup. The
`finally` block removes only the session this example created.

<!-- example: readme.create -->
```powershell
$captured = & {
    $ErrorActionPreference = 'Stop'
    $session = $server | New-TmuxSession -Name demo -WindowName editor -Command 'exec /bin/cat'
    try {
        $pane = $session | Get-TmuxPane
        $null = $pane | Split-TmuxPane -Horizontal -Command 'exec /bin/cat'
        $null = $session | New-TmuxWindow -Name logs -Command 'exec /bin/cat'
        ($server | Get-TmuxSnapshot).Sessions | Where-Object Name -CEQ demo
    } finally {
        $session | Remove-TmuxSession -Confirm:$false
    }
}
```

`$captured` is a native `LibTmux.Session`. Its `Windows` contain native
`LibTmux.Window` objects; each window's `Panes` contain native `LibTmux.Pane`
objects. The graph is still readable after cleanup:

| Expression | Captured result |
| --- | --- |
| `$captured` | A `Session` named `demo` |
| `$captured.Windows` | Two `Window` objects: `editor` and `logs` |
| `$captured.Windows[0].Panes` | Two `Pane` objects in `editor`; `logs` has one |

Walk it and filter locally:

<!-- example: readme.filter -->
```powershell
$captured.Windows |
    Where-Object { $_.Panes.Count -gt 1 } |
    Select-Object Name, @{ Name = 'PaneCount'; Expression = { $_.Panes.Count } }
```

The result is `editor` with two panes; `logs` has one. `Where-Object`,
navigation, formatting, and property access use captured data and start no
tmux client. `Get-TmuxSnapshot` explicitly reads fresh state. A linked window
can have several session placements; its index belongs to the placement.
See [snapshots and linked windows](docs/read.md) for IDs, active children and
captured versus unavailable fields.

The structured equivalent selects the one window with at least two captured
panes. `-ExactlyOne` reports zero or multiple matches:

<!-- example: readme.related -->
```powershell
$captured.Windows |
    Select-TmuxWindow -Criteria @{ 'Panes.Count' = @{ Ge = 2 } } -ExactlyOne
```

This query also performs no I/O. [The query guide](docs/query.md) shows native
predicates, Boolean and relationship criteria, and explicit fresh source
queries.

## Send a command and capture its output

Sending text means tmux accepted the keys; it does not mean the shell finished.
This example uses a unique tmux channel. The shell signals it after printing,
so capture starts only when the command has reached that point.

<!-- example: readme.input -->
```powershell
& {
    $ErrorActionPreference = 'Stop'
    $ready = 'libtmux-demo-' + [Guid]::NewGuid().ToString('N')
    $tmux = (Get-Command $server.ConnectionOptions.TmuxBinaryPath -CommandType Application |
        Select-Object -First 1).Source
    $selector = if ($server.ConnectionOptions.SocketPath) {
        "-S '{0}'" -f $server.ConnectionOptions.SocketPath.Replace("'", "'\''")
    } elseif ($server.ConnectionOptions.SocketName) {
        "-L '{0}'" -f $server.ConnectionOptions.SocketName.Replace("'", "'\''")
    } else { '' }
    $signal = "'{0}' {1} wait-for -S '{2}'" -f $tmux.Replace("'", "'\''"), $selector, $ready
    $session = $server | New-TmuxSession -Name 'input-demo' -Command 'exec /bin/sh'
    try {
        $pane = $session | Get-TmuxPane
        $pane | Send-TmuxText -Text ('printf "\nhello from PowerShell\n"; ' + $signal) -Enter
        $null = $server | Wait-TmuxChannel -Channel $ready -Timeout 10
        $pane | Get-TmuxPaneContent
    } finally {
        $session | Remove-TmuxSession -Confirm:$false
    }
}
```

The captured lines include `hello from PowerShell`. Other sessions remain
untouched; tmux may exit when this was its last session. See
[send and wait](docs/input.md) for literal
text versus keys, cancellation and a shorter recipe when completion is not
required.

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

Foreground cmdlets and `ForEach-Object -Parallel` occupy their calling pipeline.
Thread jobs return the prompt while they run; control mode keeps one client
connected for repeated commands. Watchers accept event-count and text-byte
limits. Choose a mode by its ownership and failure behavior, not a timing claim;
the [mode guide](docs/commands.md) explains when chains merge failure attribution.

## Modules and MCP

| Product | Use it for |
| --- | --- |
| [LibTmux](docs/reference/README.md) | Typed cmdlets, snapshots, input, capture, control clients and event streams |
| [LibTmux.Workspace](docs/workspace.md#plan-and-review) | Discover YAML/JSON declarations, resolve directories, review plans and create workspaces |
| [LibTmux.Mcp](docs/mcp.md#discover-before-calling) | Give an assistant tmux tools through the separately installed .NET MCP server |

Describe a two-pane workspace. Importing it parses YAML without contacting
tmux or running its commands:

<!-- example: readme.workspace.01-import -->
```powershell
$workspace = LibTmux.Workspace\Import-TmuxWorkspace -Yaml @'
session_name: readme-workspace-preview
windows:
  - window_name: editor
    panes:
      - shell_command: exec /bin/sh
      - shell_command: exec /bin/sh
'@
```

Plan on the same private endpoint. Planning may read tmux state; it does not
create the workspace:

<!-- example: readme.workspace.02-plan -->
```powershell
$workspacePlan = $workspace | LibTmux.Workspace\Get-TmuxWorkspacePlan `
    -Server $server -ServerStartup CreateOrJoin -ExistingSession Error
```

Review the actions. Their default view keeps command text, option values,
paths and environment values hidden; inspect an action's `Request` only in a
trusted terminal:

<!-- example: readme.workspace.03-review -->
```powershell
$workspacePlan.Actions
```

Preview without applying the plan:

<!-- example: readme.workspace.04-preview -->
```powershell
$workspacePlan | LibTmux.Workspace\Invoke-TmuxWorkspace -WhatIf
```

The [workspace guide](docs/workspace.md#apply-the-reviewed-plan) shows how to
apply the reviewed plan, inspect its native result and export a declaration.
For an MCP client, start with
[`list_sessions` and `capture_pane`](docs/mcp.md#discover-before-calling) after
reading its advertised capabilities.

Install both PowerShell modules at the same version. The MCP server is an
independent .NET tool and does not require PowerShell.

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

The marked README blocks run together in the
[installed workflow test](tests/ReadmeWorkflow.Tests.ps1). The
[executable guides](examples/Guides.ps1) run against real tmux through the
installed modules. See [contributing](.github/CONTRIBUTING.md) for the runners
and development checks.

The [benchmark guide](benchmarks/README.md) explains installed-package
workloads, correctness checks, raw samples and reproduction commands.
