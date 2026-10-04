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

## Install from source

Run PowerShell and tmux on the same Unix host. The module targets PowerShell
7.4 and .NET 8; the source build also needs the .NET 10 SDK, Git and Python
3.9 or newer. See [compatibility](docs/compatibility.md) for tested versions.
Install PowerShell and .NET 8 from [.tool-versions](.tool-versions) with
[mise](https://mise.jdx.dev/):

```console
$ mise install
```

Install the SDK pinned by the linked .NET source:

```console
$ mise install dotnet@10.0.302
```

Install tmux with your operating system's package manager and check that it
is on `PATH`:

```console
$ tmux -V
```

From a clean committed checkout, build the unpublished .NET dependency and
both PowerShell modules in a new sibling directory:

```console
$ pwsh -NoLogo -NoProfile -File eng/BootstrapReview.ps1 \
    -OutputDirectory "$PWD/../libtmux-powershell-review"
```

The bootstrap clones this committed revision and the
[reviewed .NET core revision](https://github.com/libtmux/libtmux-dotnet/tree/6fc8fc25ad96627a8ebb341741c9440060bca334),
builds a unique local package version, inspects its archives, and checks the
disposable lockfiles. It also packs both PowerShell modules, verifies their
archive hashes, and tests extraction, both import orders and package-manager
dependency resolution from a local feed. The printed `ModulePackages` path
and `bootstrap.json` identify the review artifacts and check receipts.

It leaves this checkout's pins and lockfiles unchanged and publishes nothing.
If a run fails, its partial output remains for inspection. Retry with a new
output directory after resolving the error.
If you already have the exact inspected archives, the
[review-package recipe](.github/CONTRIBUTING.md#review-package-builds)
shows how to consume that retained feed.

Start PowerShell with the staged module path. If you chose another output
directory, use the path printed by the bootstrap as the value of
`LIBTMUX_REVIEW_MODULE_ROOT`:

```console
$ review="$PWD/../libtmux-powershell-review"
```

```console
$ LIBTMUX_REVIEW_MODULE_ROOT="$review/port/build/Modules" \
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

Run the [quick start](examples/QuickStart.ps1) from the checkout root. It
creates a private server, splits the `editor` window, adds `logs`, and returns
a captured native `LibTmux.Session`. Show each window's pane IDs:

<!-- example: readme.quickstart -->
```powershell
(./examples/QuickStart.ps1).Windows | Select-Object Name, @{
    Name = 'PaneIds'
    Expression = { $_.Panes.Id -join ', ' }
}
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
    $session = $server |
        New-TmuxSession -Name demo -WindowName editor -Command 'exec /bin/cat'
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

## Run a command to completion

When the shell's exit status matters, run the command in a pane and inspect its
native result. This example uses the private `$server` above and removes only
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
Use the private `$server` above, wait for the application's readiness line,
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
the private endpoint from above, reads a session name, then disconnects and
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
