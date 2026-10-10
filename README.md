<!-- libtmux-logo -->
<p align="center">
  <picture>
    <source srcset="assets/logo.svg" type="image/svg+xml">
    <img src="assets/logo.png" width="128" height="128" alt="libtmux for PowerShell">
  </picture>
</p>
<!-- /libtmux-logo -->

<div align="center">

# libtmux for PowerShell

Drive [tmux](https://github.com/tmux/tmux) from PowerShell. Create sessions,
arrange panes, send input, and read terminal output through native cmdlets.
Snapshots return typed objects that you can traverse and filter with ordinary
PowerShell pipelines.

</div>

Built on [libtmux for .NET](https://github.com/libtmux/libtmux-dotnet), in the
same [libtmux organization](https://github.com/libtmux) and with the same main
author. The cmdlets return its native objects and add PowerShell parameter
binding, help, formatting and `-WhatIf` / `-Confirm`.

[Install](#install-from-source) · [Object graph](#create-and-read-an-object-graph) ·
[Run to completion](#run-a-command-to-completion) ·
[Service readiness](#wait-for-service-readiness) ·
[Execution modes](#choose-how-to-run) · [Guides](#guides) ·
[MCP](docs/mcp.md#discover-before-calling) ·
[Compatibility](docs/compatibility.md) ·
[Troubleshooting](docs/troubleshooting.md) ·
[Cmdlet reference](docs/reference/README.md) · [License](#license)

**Alpha.** APIs may change. Build from this checkout; the modules are not yet
published to PowerShell Gallery.

## Owned resource scopes

Use `-Owned` on creation and `Invoke-TmuxScope` to clean up the created resource after a PowerShell script block. `ConvertTo-TmuxOwnedResource` accepts responsibility for an existing object. The [ownership and cleanup guide](docs/lifecycle.md) covers all four object kinds, bounded socket discovery, created/reused results, pipeline cancellation and retryable failures.

## Install from source

Run PowerShell and tmux on the same Unix host. The module targets PowerShell
7.4 and .NET 8. See [compatibility](docs/compatibility.md) for tested versions.
Install PowerShell and the .NET SDK from [.tool-versions](.tool-versions) with
[mise](https://mise.jdx.dev/):

```console
$ mise install
```

Install tmux with your operating system's package manager and check that it
is on `PATH`:

```console
$ tmux -V
```

From the checkout root, restore the exact .NET versions in
[Directory.Packages.props](Directory.Packages.props) and build both PowerShell
modules. Local review versions require their matching archives in `build/nuget`:

```console
$ pwsh -NoLogo -NoProfile -File eng/Build.ps1 \
    -Restore
```

Restore checks the committed lockfiles and stages both modules under
`build/Modules`. Developing shared .NET changes uses the optional
[review-package workflow](.github/CONTRIBUTING.md#review-package-builds).
Start PowerShell with the staged module path:

```console
$ LIBTMUX_REVIEW_MODULE_ROOT="$PWD/build/Modules" \
    pwsh \
    -NoLogo \
    -NoProfile
```

Import the exact staged manifests so an older installed module cannot shadow
the new build:

<!-- example: readme.install.import -->
```powershell
$modules = $env:LIBTMUX_REVIEW_MODULE_ROOT
Import-Module -Name @(
    "$modules/LibTmux/0.1.0/LibTmux.psd1",
    "$modules/LibTmux.Workspace/0.1.0/LibTmux.Workspace.psd1"
) -ErrorAction Stop
```

The commands below run in that PowerShell session. The workspace module is
installed alongside the core module; the MCP server is a separate .NET tool.
Use `Get-Command -Module LibTmux` to browse cmdlets and
`Get-Help LibTmux\New-TmuxSession -Examples` for installed examples.

## Start or reuse a workspace

Copy this program into PowerShell with `LibTmux` installed. It starts a missing daemon or reuses the selected one, then finds or creates `libtmux-demo` and its `logs` window. The workspace stays available after the program returns. Repeating the program reuses those names.

<!-- example: readme.ordinary -->
```powershell
Import-Module LibTmux

$server = Start-TmuxServer -ErrorAction Stop
$session = ($server | Resolve-TmuxSession -Name libtmux-demo `
    -Request @{ WindowName = 'editor' } -ErrorAction Stop).Value
$null = $session | Resolve-TmuxWindow -Name logs -ErrorAction Stop

($server | Get-TmuxSnapshot -ErrorAction Stop).Sessions |
    Select-TmuxSession -Criteria @{ Name = 'libtmux-demo' } -ExactlyOne
```

`Start-TmuxServer` returns an ordinary `LibTmux.Server`. It uses normal tmux defaults; an existing server keeps its sessions and configuration. For a new daemon, startup creates and removes a temporary session and sets the server's `exit-empty` option to `off`, so it remains available before you create your first session. Startup still reads the normal tmux configuration. The program has no cleanup owner to close.

`LIBTMUX_SOCKET_PATH` or `LIBTMUX_SOCKET_NAME` can redirect this unchanged program. The test harness supplies these variables only to its children and cleans up its own daemon afterward. See [ordinary example testing](docs/ordinary-examples.md) for cold-start, reuse and interruption checks, and [ownership and cleanup](docs/lifecycle.md) for explicit destruction scopes.

## Capture a graph and clean up its session

This example demonstrates explicit cleanup after success and failure.

Run the [session-cleanup example](examples/SessionCleanup.ps1) from the checkout root. It
creates a session, splits the `editor` window, adds `logs`, and returns
a captured native `LibTmux.Session`. Show each window's pane IDs:

<!-- example: readme.quickstart -->
```powershell
(./examples/SessionCleanup.ps1).Windows | Select-Object Name, @{
    Name = 'PaneIds'
    Expression = { $_.Panes.Id -join ', ' }
}
```

Example output (pane IDs depend on the selected server):

```text
Name   PaneIds
----   -------
editor %0, %1
logs   %2
```

Assign `./examples/SessionCleanup.ps1` to a variable to keep the session object.
Its `Windows` and `Panes` remain readable after the script removes its session.
The script imports `LibTmux` and uses `New-TmuxServer` with ordinary defaults.
The constructor selects an explicit socket argument first, then
`LIBTMUX_SOCKET_PATH`, `LIBTMUX_SOCKET_NAME`, `TMUX`, or tmux's named default.
An empty selector variable counts as absent. The script takes no socket
arguments; its caller can redirect it through those environment variables.
The script removes the session it created by ID, including after a body
failure. If the body and cleanup fail, it throws an `AggregateException` with
both errors. An existing `demo` session causes creation to fail without
removing that session.

## Create, capture and clean up an object graph

`New-TmuxServer` captures the selected endpoint and child process environment
without contacting tmux. Later host-environment changes cannot redirect the
handle. It borrows the endpoint; creating a handle gives no responsibility
for destroying a daemon.

<!-- example: readme.endpoint -->
```powershell
if (!(Get-Module LibTmux)) { Import-Module LibTmux -ErrorAction Stop }
$server = LibTmux\New-TmuxServer
```

Create the same graph and retain its snapshot. `cat` keeps the
three panes open without shell setup. The `finally` block removes
the created session and preserves a cleanup failure alongside a body failure.

<!-- example: readme.create -->
```powershell
$captured = & {
    $ErrorActionPreference = 'Stop'
    $command = 'exec /bin/cat'
    $session = $null
    $bodyError = $null
    try {
        $session = $server |
            New-TmuxSession -Name demo -WindowName editor -Command $command
        $pane = $session | Get-TmuxPane
        $null = $pane | Split-TmuxPane -Horizontal -Command $command
        $null = $session | New-TmuxWindow -Name logs -Command $command

        $captured = ($server | Get-TmuxSnapshot).Sessions |
            Select-TmuxSession -Criteria @{ Name = 'demo' } -ExactlyOne
        $captured
    } catch {
        $bodyError = $_
        throw
    } finally {
        if ($session) {
            try { $session | Remove-TmuxSession -Confirm:$false }
            catch {
                if ($bodyError) {
                    throw [AggregateException]::new(
                        'Session body and cleanup failed.',
                        [Exception[]] @($bodyError.Exception, $_.Exception))
                }
                throw
            }
        }
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

## Run a command to completion

When the shell's exit status matters, run the command in a pane and inspect its
native result. This example uses the selected `$server` above and removes only
the session it creates:

<!-- example: input.run -->
```powershell
& {
    $ErrorActionPreference = 'Stop'
    $name = 'pane-run-' + [Guid]::NewGuid().ToString('N')
    $session = $server | New-TmuxSession -Name $name -Command 'exec /bin/sh'
    try {
        $pane = $session | Get-TmuxPane
        $pane |
            Invoke-TmuxPaneCommand -Command 'exit 7' -Timeout 5 -Confirm:$false
    } finally {
        $session | Remove-TmuxSession -Confirm:$false
    }
}
```

The result has `ExitStatus = 7` and `TimedOut = False`. A nonzero shell exit is
a result, not a tmux error. On timeout, the command may still be running, so
the result has no exit status. See [command completion](docs/input.md#run-a-command-to-completion)
for concurrency and output behavior.

## Wait for service readiness

With Python 3 on `PATH`, start an HTTP server on an available loopback port.
Use the selected `$server` above, wait for the application's readiness line,
then make an HTTP request to check that it responds. The session's cleanup
also stops the server process:

<!-- example: input.http-ready -->
```powershell
& {
    $ErrorActionPreference = 'Stop'
    $session = $server | New-TmuxSession `
        -Name ('http-' + [Guid]::NewGuid().ToString('N')) `
        -Command 'exec python3 -u -m http.server 0 --bind 127.0.0.1'
    try {
        $pane = $session | Get-TmuxPane
        $ready = $pane | Wait-TmuxPaneText `
            -Pattern '^Serving HTTP on 127\.0\.0\.1 port [0-9]+' `
            -CaseSensitive -Timeout 10 -TailLines 4 -Confirm:$false
        if ($ready.Outcome -notin 'PresentAtEntry', 'Matched') {
            throw "HTTP readiness ended with $($ready.Outcome)."
        }
        $tail = $ready.Tail -join "`n"
        $port = [regex]::Match($tail, 'port ([0-9]+)').Groups[1].Value
        $uri = "http://127.0.0.1:$port/"
        $response = Invoke-WebRequest -Uri $uri -TimeoutSec 5 -NoProxy
        $ready
        $response.StatusCode
    } finally {
        $session | Remove-TmuxSession -Confirm:$false
    }
}
```

The native `PaneWaitResult` has outcome `PresentAtEntry` or `Matched`,
followed by HTTP status 200. The wait closes its temporary control client;
the example removes only its session. A text match proves the readiness
condition, and the HTTP request checks service behavior separately.
See [pane-text waits](docs/input.md#wait-for-an-applications-readiness-line)
for stop patterns, bounded tails, cancellation and disclosed event loss.
Use [a cooperative channel](docs/input.md#send-a-command-and-wait-for-its-output)
when the application can signal completion itself.

## Choose how to run

| Task | Use | Example |
| --- | --- | --- |
| Read or change tmux state | Typed cmdlets and pipelines | [Create sessions and panes](docs/create.md) |
| Run a shell command and check its exit status | `Invoke-TmuxPaneCommand` | [Run to completion](docs/input.md#run-a-command-to-completion) |
| Wait for a running application's readiness line | `Wait-TmuxPaneText` | [Readiness and an HTTP health check](#wait-for-service-readiness) |
| Enter a session interactively | `Enter-TmuxSession` | [Attach your foreground terminal](docs/reference/LibTmux/Enter-TmuxSession.md) |
| Run an ordered batch | `New-TmuxCommand` → `Invoke-TmuxChain` | [Compose commands](docs/commands.md) |
| Reuse a connected client | `Connect-TmuxControl` → `Invoke-TmuxControlCommand` | [Control commands and cleanup](docs/commands.md) |
| React to output and notifications | `Watch-TmuxEvent` | [Bounded event streams](docs/watch.md) |
| Keep the prompt available | `Start-ThreadJob` | [Bounded background jobs](docs/watch.md#bound-background-output) |
| Run commands concurrently | `ForEach-Object -Parallel` | [Independent clients](docs/watch.md#run-independent-commands-concurrently) |

Connect once to send a command through tmux control mode. This example uses
the endpoint from above, reads a session name, then disconnects and
removes the session it created:

<!-- example: readme.control -->
```powershell
& {
    $ErrorActionPreference = 'Stop'
    $session = $server |
        New-TmuxSession -Name control-demo -Command 'exec /bin/cat'
    try {
        $client = $server |
            Connect-TmuxControl -Target 'control-demo' -ErrorAction Stop
        try {
            $command = New-TmuxCommand -Name display-message -Arguments @(
                '-p', '#{session_name}'
            )
            $client |
                Invoke-TmuxControlCommand -Command $command -ErrorAction Stop
        } finally {
            $client | Disconnect-TmuxControl -Confirm:$false
        }
    } finally {
        $session | Remove-TmuxSession -Confirm:$false
    }
}
```

The reply is `control-demo`. The client stays connected across commands inside
the inner `try` block; use the [control guide](docs/commands.md#reuse-a-control-client)
for multiple commands and cancellation behavior.

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

Plan on the same endpoint. Planning may read tmux state; it does not
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

Apply that exact plan, then remove only the session it created. The captured
result remains readable after cleanup:

<!-- example: readme.workspace.05-apply -->
```powershell
$workspaceResult = & {
    $result = $workspacePlan |
        LibTmux.Workspace\Invoke-TmuxWorkspace -Confirm:$false -ErrorAction Stop
    try { $result } finally {
        $result.Session | Remove-TmuxSession -Confirm:$false
    }
}
```

<!-- example: readme.workspace.06-graph -->
```powershell
$workspaceResult.Windows |
    Select-Object Name, @{ Name = 'PaneCount'; Expression = { $_.Panes.Count } }
```

This returns `editor` with two panes. The
[workspace guide](docs/workspace.md#apply-the-reviewed-plan) covers failure
recovery, attaching and exporting a declaration. For an MCP client, start with
the [client configuration](docs/mcp.md#install-and-select-a-server), then read
`tools/list` and `tmux://capabilities` before calling
[`list_sessions` or `capture_pane`](docs/mcp.md#discover-before-calling).

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

## License

[MIT](LICENSE). Bundled dependency notices are in [licenses](licenses/).
