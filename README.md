<!-- libtmux-logo -->
<div align="center">
  <picture>
    <source srcset="assets/logo.svg" type="image/svg+xml">
    <img src="assets/logo.png" width="128" height="128" alt="libtmux for PowerShell">
  </picture>
</div>
<!-- /libtmux-logo -->

<div align="center">

# libtmux for PowerShell

[![powershell](https://github.com/libtmux/libtmux-powershell/actions/workflows/ci.yml/badge.svg)](https://github.com/libtmux/libtmux-powershell/actions/workflows/ci.yml)
[![LibTmux](https://img.shields.io/powershellgallery/v/LibTmux?label=LibTmux)](https://www.powershellgallery.com/packages/LibTmux/)
[![libtmux.org](https://img.shields.io/badge/docs-libtmux.org-0b7285)](https://libtmux.org/en/powershell/)
[![license](https://img.shields.io/badge/license-MIT-blue)](https://github.com/libtmux/libtmux-powershell/blob/master/LICENSE)

Drive [tmux](https://github.com/tmux/tmux) from PowerShell with native cmdlets.
[Sessions][session], [windows][window] and [panes][pane] come back as typed
objects that an ordinary pipeline can filter.

</div>

Run a command and read its exit status with
[`Invoke-TmuxPaneCommand`][invoke-tmuxpanecommand], find what a server holds
with [`Get-TmuxSnapshot`][get-tmuxsnapshot], wait for output with
[`Wait-TmuxPaneText`][wait-tmuxpanetext], and apply a reviewed workspace file
with [`Invoke-TmuxWorkspace`][invoke-tmuxworkspace].

Releases are numbered `0.1.N`, and each release increments `N`. The API is not
settled: any release may change or remove exported identifiers, and the
changelog marks each break. Pin an exact version to avoid one.

Both modules are available on PowerShell Gallery:
[LibTmux](https://www.powershellgallery.com/packages/LibTmux)
and [LibTmux.Workspace](https://www.powershellgallery.com/packages/LibTmux.Workspace).

It needs PowerShell 7.4 or later and tmux 3.3a or newer on the same Linux
host, including WSL. [Compatibility](docs/compatibility.md) lists what CI runs.

tmux release candidates are not supported: a feature can require one only
until its release ships, and a candidate such as `X.Y-rcN` ranks below `X.Y`.
See [Release candidates](https://libtmux.org/en/tmux/guides/tmux-support/#release-candidates).

**Contents** — [Quick start](#quick-start) ·
[Find things](#find-sessions-windows-and-panes) ·
[Service readiness](#wait-for-service-readiness) ·
[Choose how to run](#choose-how-to-run) ·
[Workspaces](#build-a-workspace-from-a-file) · [Packages](#packages) ·
[From source](#install-from-source) · [Leaves out](#what-it-leaves-out) ·
[Support](#support-and-status) · [Documentation](#documentation)

**Reference** — [Cmdlet reference](docs/reference/README.md) ·
[Compatibility](docs/compatibility.md) ·
[Troubleshooting](docs/troubleshooting.md) ·
[MCP](docs/mcp.md#discover-before-calling) · [License](#license)

## Quick start

Install the module from the PowerShell Gallery in PowerShell 7.4 or later
(`pwsh`) on Linux, including WSL. `Install-PSResource` ships with PowerShell
7.4; Windows PowerShell 5.1 has no such command and cannot load the module:

```console
$ Install-PSResource -Name LibTmux
```

Import it:

```console
$ Import-Module -Name LibTmux -ErrorAction Stop
```

[`New-TmuxServer`][new-tmuxserver] makes a handle on a socket and an empty tmux
configuration of its own. It contacts nothing, so your default server stays
untouched:

<!-- example: read.endpoint -->
```powershell
$server = LibTmux\New-TmuxServer `
    -SocketName ('libtmux-readme-' + [Guid]::NewGuid().ToString('N')) `
    -ConfigurationFile /dev/null
```

[`Invoke-TmuxPaneCommand`][invoke-tmuxpanecommand] runs a command in a pane and
returns a [`LibTmux.PaneRunResult`][panerunresult].
[`New-TmuxSession`][new-tmuxsession] starts the shell, and the `finally` block
removes only that session with [`Remove-TmuxSession`][remove-tmuxsession]:

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

The result has `ExitStatus = 7` and `TimedOut = False`. A nonzero exit status
comes back in `ExitStatus` and raises no error. If the timeout passes first, the
command may still be running and the result has no exit status.

[Command completion](docs/input.md#run-a-command-to-completion) covers
concurrency and output behavior.

Every PowerShell block on this page is a copy of a tested source. The
[guide test](https://github.com/libtmux/libtmux-powershell/blob/master/tests/GuideExamples.Tests.ps1)
fails when a copy drifts, and the
[installed workflow test](https://github.com/libtmux/libtmux-powershell/blob/master/tests/ReadmeWorkflow.Tests.ps1)
runs the blocks in order on an owned tmux server. Later sections reuse
`$server`.

## Find sessions, windows, and panes

### [`Get-TmuxSnapshot`][get-tmuxsnapshot]: what tmux holds, in one read

One call returns every session, window and pane as native objects.

This example builds a tree with [`New-TmuxSession`][new-tmuxsession],
[`Split-TmuxPane`][split-tmuxpane] and [`New-TmuxWindow`][new-tmuxwindow],
reads it, and removes it with [`Remove-TmuxSession`][remove-tmuxsession]. `cat`
keeps the panes open:

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

`$captured` is a [`LibTmux.Session`][session] that stays readable after
cleanup. Its [`Windows`][session-windows] hold [`LibTmux.Window`][window]
objects, and each window's [`Panes`][window-panes] hold
[`LibTmux.Pane`][pane] objects:

| Expression | Captured result |
| --- | --- |
| `$captured` | A `Session` named `demo` |
| [`$captured.Windows`][session-windows] | Two `Window` objects: `editor` and `logs` |
| [`$captured.Windows[0].Panes`][window-panes] | Two `Pane` objects in `editor`; `logs` has one |

A captured object keeps what tmux reported when you read it. Call
[`Get-TmuxSnapshot`][get-tmuxsnapshot] again to see a later change.
[Snapshots and linked windows](docs/read.md) cover IDs, active children and
captured versus unavailable fields.

### Filter the captured graph

Walk it with ordinary PowerShell. `Where-Object`, navigation, formatting and
property access use the captured data and start no tmux client:

<!-- example: readme.filter -->
```powershell
$captured.Windows |
    Where-Object { $_.Panes.Count -gt 1 } |
    Select-Object Name, @{ Name = 'PaneCount'; Expression = { $_.Panes.Count } }
```

It prints `editor` with a pane count of 2. `logs` has one pane and drops out:

```text
Name   PaneCount
----   ---------
editor         2
```

### [`Select-TmuxWindow`][select-tmuxwindow]: pick windows by criteria

The structured equivalent selects the one window with at least two captured
panes. `-ExactlyOne` reports zero or multiple matches. This query performs no
I/O either:

<!-- example: readme.related -->
```powershell
$captured.Windows |
    Select-TmuxWindow -Criteria @{ 'Panes.Count' = @{ Ge = 2 } } -ExactlyOne
```

It returns the `editor` window, the same object as `$captured.Windows[0]`.
[The query guide](docs/query.md) shows native predicates, Boolean and
relationship criteria, and explicit fresh source queries.

## Wait for service readiness

### [`Wait-TmuxPaneText`][wait-tmuxpanetext]: wait for a readiness line

It watches a pane's rendered text through a temporary control client and
returns a [`LibTmux.PaneWaitResult`][panewaitresult].

[`Send-TmuxText`][send-tmuxtext] and [`Send-TmuxKey`][send-tmuxkey] type into
the pane first, and [`Get-TmuxPaneContent`][get-tmuxpanecontent] reads its
screen. When the application can signal completion itself, use
[`Wait-TmuxChannel`][wait-tmuxchannel] with
[a cooperative channel](docs/input.md#send-a-command-and-wait-for-its-output).

With Python 3 on `PATH`, this example starts an HTTP server on a free loopback
port, waits for its readiness line, then requests a page. The session's cleanup
also stops the server:

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

The outcome is `PresentAtEntry` or `Matched`, followed by HTTP status 200. The
wait closes its control client, and the example removes only its own session.

A text match shows the readiness line; the HTTP request checks the service.
[Pane-text waits](docs/input.md#wait-for-an-applications-readiness-line) cover
stop patterns, bounded tails, cancellation and disclosed event loss.

## Choose how to run

Pick a mode by who owns the client and how a failure is reported:

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

An older daemon refuses these before anything changes:
[`Invoke-TmuxPaneCommand`][invoke-tmuxpanecommand] needs tmux 3.4, and
[`Connect-TmuxControl`][connect-tmuxcontrol] and
[`Watch-TmuxEvent`][watch-tmuxevent] with a server need 3.7.

Other commands are refused on the releases they harm. The
[optional features](docs/compatibility.md#optional-features) table lists each
one, and [`capabilities.json`](capabilities.json) holds the same list for an
assistant or a script to read.

The raw-command cmdlets [`Invoke-TmuxCommand`][invoke-tmuxcommand],
[`Invoke-TmuxChain`][invoke-tmuxchain] and
[`Invoke-TmuxControlCommand`][invoke-tmuxcontrolcommand] check the command
they are given and nothing nested in it, such as an `if-shell` string, a
`bind-key` command or a brace block.

On exactly tmux 3.7, name every `break-pane`, including the one `prefix !`
runs, or upgrade to 3.7a: a nested nameless one ends the server.
[What the checks do not read](docs/compatibility.md#what-the-checks-do-not-read)
lists the other failures.

### [`Connect-TmuxControl`][connect-tmuxcontrol]: one client for repeated commands

It connects one control client. [`New-TmuxCommand`][new-tmuxcommand] builds a
command, [`Invoke-TmuxControlCommand`][invoke-tmuxcontrolcommand] sends it
through the client, and [`Disconnect-TmuxControl`][disconnect-tmuxcontrol] ends
it. [`Invoke-TmuxChain`][invoke-tmuxchain] sends an ordered batch in one
invocation.

This example uses the private endpoint from above, reads a session name, then
disconnects and removes the session it created:

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
the inner `try` block. The [control guide](docs/commands.md#reuse-a-control-client)
covers multiple commands and cancellation.

The other modes in short:

- [`Enter-TmuxSession`][enter-tmuxsession] attaches your foreground terminal to
  a session.
- Foreground cmdlets and `ForEach-Object -Parallel` occupy their calling
  pipeline.
- Thread jobs return the prompt while they run.
- [`Watch-TmuxEvent`][watch-tmuxevent] accepts event-count and text-byte limits.

The [mode guide](docs/commands.md) explains when chains merge failure
attribution.

## Build a workspace from a file

Describe a session once in YAML or JSON, review the plan, then apply it.
Installing the workspace module also installs its exact core dependency:

```console
$ Install-PSResource -Name LibTmux.Workspace
```

Import both modules:

```console
$ Import-Module -Name LibTmux, LibTmux.Workspace -ErrorAction Stop
```

### [`Import-TmuxWorkspace`][import-tmuxworkspace]: read a declaration

It parses YAML or JSON without contacting tmux or running the commands in it.

[`Get-TmuxWorkspace`][get-tmuxworkspace] finds declaration files,
[`Resolve-TmuxWorkspace`][resolve-tmuxworkspace] expands directories and
[`Test-TmuxWorkspace`][test-tmuxworkspace] validates one. This declaration has
two panes in one window:

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

It returns a [`LibTmux.Workspace.WorkspaceFile`][workspacefile] and prints
nothing.

### [`Get-TmuxWorkspacePlan`][get-tmuxworkspaceplan]: review before anything runs

It plans on the same private endpoint. Planning may read tmux state and creates
nothing:

<!-- example: readme.workspace.02-plan -->
```powershell
$workspacePlan = $workspace | LibTmux.Workspace\Get-TmuxWorkspacePlan `
    -Server $server -ServerStartup CreateOrJoin -ExistingSession Error
```

Review the actions. Their default view keeps command text, option values, paths
and environment values hidden; inspect an action's
[`Request`][workspaceaction-request] only in a trusted terminal:

<!-- example: readme.workspace.03-review -->
```powershell
$workspacePlan.Actions
```

It lists the actions in order, from
[`CreateSession`][workspaceactionkind-createsession] to
[`CaptureResult`][workspaceactionkind-captureresult], with command text shown
as `[redacted]`.

### [`Invoke-TmuxWorkspace`][invoke-tmuxworkspace]: preview, then apply

`-WhatIf` previews the plan without applying it:

<!-- example: readme.workspace.04-preview -->
```powershell
$workspacePlan | LibTmux.Workspace\Invoke-TmuxWorkspace -WhatIf
```

It prints a `What if:` line followed by the plan's actions. Apply that exact
plan, then remove only the session it created. The captured result stays
readable after cleanup:

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

The result is a [`LibTmux.Workspace.WorkspaceResult`][workspaceresult]. Read its
windows:

<!-- example: readme.workspace.06-graph -->
```powershell
$workspaceResult.Windows |
    Select-Object Name, @{ Name = 'PaneCount'; Expression = { $_.Panes.Count } }
```

This returns `editor` with two panes. The
[workspace guide](docs/workspace.md#apply-the-reviewed-plan) covers failure
recovery, attaching and exporting a declaration;
[`ConvertTo-TmuxWorkspace`][convertto-tmuxworkspace] turns a captured session
into a starting declaration.

## Packages

| Product | Use it for |
| --- | --- |
| [LibTmux](docs/reference/README.md) | Typed cmdlets, snapshots, input, capture, control clients and event streams |
| [LibTmux.Workspace](docs/workspace.md#plan-and-review) [![LibTmux.Workspace](https://img.shields.io/powershellgallery/v/LibTmux.Workspace?label=LibTmux.Workspace)](https://www.powershellgallery.com/packages/LibTmux.Workspace) | Discover YAML/JSON declarations, resolve directories, review plans and create workspaces |
| [LibTmux.Mcp](docs/mcp.md#discover-before-calling) | Give an assistant tmux tools through the separately installed .NET MCP server |

### [LibTmux](https://github.com/libtmux/libtmux-powershell/tree/master/src/LibTmux.PowerShell): typed cmdlets for tmux

Read, create, arrange and remove sessions, windows and panes, send input and
capture output as native objects. The walkthroughs above run on the installed
module:

- [Read an object graph](#find-sessions-windows-and-panes) with
  [`Get-TmuxSnapshot`][get-tmuxsnapshot] and
  [`Select-TmuxWindow`][select-tmuxwindow].
- [Check a command's exit status](#quick-start) with
  [`Invoke-TmuxPaneCommand`][invoke-tmuxpanecommand].
- [Wait for a readiness line](#wait-for-service-readiness) with
  [`Wait-TmuxPaneText`][wait-tmuxpanetext].
- [Choose an execution mode](#choose-how-to-run), including
  [`Watch-TmuxEvent`][watch-tmuxevent].

Reference: [every LibTmux cmdlet][libtmux-module] and the
[PowerShell Gallery page](https://www.powershellgallery.com/packages/LibTmux).

### [LibTmux.Workspace](https://github.com/libtmux/libtmux-powershell/tree/master/src/LibTmux.Workspace.PowerShell): workspaces from YAML or JSON

Describe a session once, review the plan, then apply it. The commands below run
in this order:

- [`Get-TmuxWorkspace`][get-tmuxworkspace] finds declaration files.
- [`Import-TmuxWorkspace`][import-tmuxworkspace] parses YAML or JSON without
  contacting tmux.
- [`Resolve-TmuxWorkspace`][resolve-tmuxworkspace] expands directories and
  [`Test-TmuxWorkspace`][test-tmuxworkspace] validates the declaration.
- [`Get-TmuxWorkspacePlan`][get-tmuxworkspaceplan] plans against a server and
  [`Invoke-TmuxWorkspace`][invoke-tmuxworkspace] applies the reviewed plan;
  `-WhatIf` previews it.
- [`ConvertTo-TmuxWorkspace`][convertto-tmuxworkspace] turns a captured session
  into a starting declaration.

[Install it](#build-a-workspace-from-a-file) with the core module, at the same
version. Reference: [every LibTmux.Workspace cmdlet][workspace-module] and the
[PowerShell Gallery page](https://www.powershellgallery.com/packages/LibTmux.Workspace).

### [LibTmux.Mcp](https://github.com/libtmux/libtmux-dotnet/tree/master/src/LibTmux.Mcp): tmux tools for assistants

A separate .NET tool that lets an MCP client list, read and drive tmux panes. It
needs no PowerShell. Reference: the
[MCP guide](https://libtmux.org/en/powershell/latest/guides/mcp/), the
[tool reference](https://libtmux.org/en/csharp/latest/mcp/tools/) and
[NuGet](https://www.nuget.org/packages/LibTmux.Mcp).

Install the tool on the Unix host that runs tmux:

```console
$ dotnet tool install --global LibTmux.Mcp \
    --version 0.1.0 \
    --framework net8.0
```

Register it with Claude Code. This names the tmux socket `work` and offers only
the tools that read tmux:

```console
$ claude mcp add tmux \
    -e LIBTMUX_SOCKET=work \
    -e LIBTMUX_TOOLSETS=inspect \
    -- libtmux-mcp
```

A client that reads a JSON configuration takes the same command and settings:

```json
{
  "mcpServers": {
    "tmux": {
      "command": "libtmux-mcp",
      "env": { "LIBTMUX_SOCKET": "work", "LIBTMUX_TOOLSETS": "inspect" }
    }
  }
}
```

- Find a pane with [`list_sessions`][mcp-list_sessions],
  [`list_windows`][mcp-list_windows] and [`list_panes`][mcp-list_panes].
- Read it with [`capture_pane`][mcp-capture_pane], or
  [`snapshot_pane`][mcp-snapshot_pane] for structured state.
- Wait for output with [`wait_for_text`][mcp-wait_for_text] and a finite timeout.
- Read the selected tools and socket from the
  [`tmux://capabilities` resource][mcp-capabilities] before calling any tool.

The [MCP guide](docs/mcp.md) covers
[client configuration](docs/mcp.md#install-and-select-a-server),
[discovery before calling](docs/mcp.md#discover-before-calling), finite waits
and the other toolsets.
[Its test](docs/mcp.md#check-the-client-workflow-from-this-checkout) starts the
installed tool with these settings and checks what it reports.

## Install from source

Install the pinned PowerShell and .NET SDK from [.tool-versions](.tool-versions)
with [mise](https://mise.jdx.dev/):

```console
$ mise install
```

Install tmux with your operating system's package manager and check that it
is on `PATH`:

```console
$ tmux -V
```

From the checkout root, restore the published
[.NET 0.1.0 packages](https://www.nuget.org/packages/LibTmux/0.1.0)
and build both PowerShell modules:

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

### [`examples/QuickStart.ps1`](examples/QuickStart.ps1): a private server and three panes

Run the [quick start](examples/QuickStart.ps1) from the checkout root. It
creates a private server, splits the `editor` window, adds `logs`, and returns
a captured [`LibTmux.Session`][session]. Show each window's pane IDs:

<!-- example: readme.quickstart -->
```powershell
(./examples/QuickStart.ps1).Windows | Select-Object Name, @{
    Name = 'PaneIds'
    Expression = { $_.Panes.Id -join ', ' }
}
```

It prints the pane IDs from the private server:

```text
Name   PaneIds
----   -------
editor %0, %1
logs   %2
```

Assign `./examples/QuickStart.ps1` to a variable to keep the session object. Its
[`Windows`][session-windows] and [`Panes`][session-panes] remain readable after
the script removes its session. The script uses a unique socket, so your
default tmux server stays untouched.

## What it leaves out

- **Live objects.** A captured object keeps what tmux reported when you read it.
  [`Get-TmuxSnapshot`][get-tmuxsnapshot] reads again, and
  [snapshots and linked windows](docs/read.md) list what a capture cannot know.
- **An implicit server.** A handle from [`New-TmuxServer`][new-tmuxserver]
  starts no daemon, and importing the module connects to none. The module
  leaves `TMUX` and `TMUX_PANE` in your session as they are
  ([compatibility](docs/compatibility.md)).
- **Shell quoting.** [`Send-TmuxText`][send-tmuxtext] sends its text literally
  and does not quote it for the shell that receives it
  ([send input](docs/input.md)).
- **Native Windows.** Run PowerShell and tmux inside WSL, in one Linux
  environment. Native Windows and psmux are outside this port
  ([compatibility](docs/compatibility.md)).
- **The MCP server.** LibTmux.Mcp is a separate .NET tool that needs no
  PowerShell, and the modules install none of its tools
  ([MCP guide](docs/mcp.md)).

## Support and status

- **Releases.** Releases are numbered `0.1.N`, and each release increments `N`.
  The API is not settled: any release may change or remove exported
  identifiers, and the changelog marks each break. Pin an exact version to
  avoid one.
- **PowerShell.** 7.4 or later. CI runs 7.4.20 and 7.6.6.
- **tmux.** 3.3a or newer. CI runs 3.3a and 3.8 on every change, and 3.3a
  through 3.8 and tmux master before a release; other releases are
  unverified. [Compatibility](docs/compatibility.md) holds the contract.
- **Systems.** Linux, including WSL: run PowerShell and tmux in the same Linux
  environment. CI runs Linux x64 on every change and macOS as an advisory trial
  whose failures never fail the check. CI has no Windows job.
- **Built on [libtmux for .NET](https://github.com/libtmux/libtmux-dotnet).**
  It lives in the same [libtmux organization](https://github.com/libtmux) with
  the same main author. The cmdlets return its native objects and add
  PowerShell parameter binding, help, formatting and `-WhatIf` / `-Confirm`.

## Documentation

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

Browse cmdlets with `Get-Command -Module LibTmux` and examples with
`Get-Help LibTmux\New-TmuxSession -Examples`. Further reading:

- [Compatibility](docs/compatibility.md) — what CI runs and the support contract
- [Troubleshooting](docs/troubleshooting.md) — endpoint, package, input and
  stream failures
- [Benchmarks](benchmarks/README.md) — installed-package workloads,
  correctness checks, raw samples and reproduction commands
- [Contributing](.github/CONTRIBUTING.md) — the runners and development checks
- [Executable guides](examples/Guides.ps1) — run against real tmux through the
  installed modules, and the README blocks run together in the
  [installed workflow test](tests/ReadmeWorkflow.Tests.ps1)

## License

[MIT](LICENSE). See [third-party notices](licenses/THIRD-PARTY-NOTICES.md)
for bundled dependencies.

[libtmux-module]: https://libtmux.org/en/powershell/latest/reference/
[workspace-module]: https://libtmux.org/en/powershell/latest/workspace/reference/
[new-tmuxserver]: https://libtmux.org/en/powershell/latest/reference/libtmux-new-tmuxserver/
[new-tmuxsession]: https://libtmux.org/en/powershell/latest/reference/libtmux-new-tmuxsession/
[split-tmuxpane]: https://libtmux.org/en/powershell/latest/reference/libtmux-split-tmuxpane/
[new-tmuxwindow]: https://libtmux.org/en/powershell/latest/reference/libtmux-new-tmuxwindow/
[get-tmuxsnapshot]: https://libtmux.org/en/powershell/latest/reference/libtmux-get-tmuxsnapshot/
[remove-tmuxsession]: https://libtmux.org/en/powershell/latest/reference/libtmux-remove-tmuxsession/
[select-tmuxwindow]: https://libtmux.org/en/powershell/latest/reference/libtmux-select-tmuxwindow/
[invoke-tmuxpanecommand]: https://libtmux.org/en/powershell/latest/reference/libtmux-invoke-tmuxpanecommand/
[wait-tmuxpanetext]: https://libtmux.org/en/powershell/latest/reference/libtmux-wait-tmuxpanetext/
[send-tmuxtext]: https://libtmux.org/en/powershell/latest/reference/libtmux-send-tmuxtext/
[send-tmuxkey]: https://libtmux.org/en/powershell/latest/reference/libtmux-send-tmuxkey/
[get-tmuxpanecontent]: https://libtmux.org/en/powershell/latest/reference/libtmux-get-tmuxpanecontent/
[wait-tmuxchannel]: https://libtmux.org/en/powershell/latest/reference/libtmux-wait-tmuxchannel/
[connect-tmuxcontrol]: https://libtmux.org/en/powershell/latest/reference/libtmux-connect-tmuxcontrol/
[new-tmuxcommand]: https://libtmux.org/en/powershell/latest/reference/libtmux-new-tmuxcommand/
[invoke-tmuxcontrolcommand]: https://libtmux.org/en/powershell/latest/reference/libtmux-invoke-tmuxcontrolcommand/
[disconnect-tmuxcontrol]: https://libtmux.org/en/powershell/latest/reference/libtmux-disconnect-tmuxcontrol/
[invoke-tmuxchain]: https://libtmux.org/en/powershell/latest/reference/libtmux-invoke-tmuxchain/
[invoke-tmuxcommand]: https://libtmux.org/en/powershell/latest/reference/libtmux-invoke-tmuxcommand/
[watch-tmuxevent]: https://libtmux.org/en/powershell/latest/reference/libtmux-watch-tmuxevent/
[enter-tmuxsession]: https://libtmux.org/en/powershell/latest/reference/libtmux-enter-tmuxsession/
[get-tmuxworkspace]: https://libtmux.org/en/powershell/latest/workspace/reference/libtmux-workspace-get-tmuxworkspace/
[import-tmuxworkspace]: https://libtmux.org/en/powershell/latest/workspace/reference/libtmux-workspace-import-tmuxworkspace/
[resolve-tmuxworkspace]: https://libtmux.org/en/powershell/latest/workspace/reference/libtmux-workspace-resolve-tmuxworkspace/
[test-tmuxworkspace]: https://libtmux.org/en/powershell/latest/workspace/reference/libtmux-workspace-test-tmuxworkspace/
[get-tmuxworkspaceplan]: https://libtmux.org/en/powershell/latest/workspace/reference/libtmux-workspace-get-tmuxworkspaceplan/
[invoke-tmuxworkspace]: https://libtmux.org/en/powershell/latest/workspace/reference/libtmux-workspace-invoke-tmuxworkspace/
[convertto-tmuxworkspace]: https://libtmux.org/en/powershell/latest/workspace/reference/libtmux-workspace-convertto-tmuxworkspace/
[session]: https://libtmux.org/en/csharp/latest/reference/libtmux-session/
[window]: https://libtmux.org/en/csharp/latest/reference/libtmux-window/
[pane]: https://libtmux.org/en/csharp/latest/reference/libtmux-pane/
[session-windows]: https://libtmux.org/en/csharp/latest/reference/libtmux-session-windows/
[window-panes]: https://libtmux.org/en/csharp/latest/reference/libtmux-window-panes/
[session-panes]: https://libtmux.org/en/csharp/latest/reference/libtmux-session-panes/
[panerunresult]: https://libtmux.org/en/csharp/latest/reference/libtmux-panerunresult/
[panewaitresult]: https://libtmux.org/en/csharp/latest/reference/libtmux-panewaitresult/
[workspacefile]: https://libtmux.org/en/csharp/latest/workspace/reference/libtmux-workspace-workspacefile/
[workspaceresult]: https://libtmux.org/en/csharp/latest/workspace/reference/libtmux-workspace-workspaceresult/
[workspaceaction-request]: https://libtmux.org/en/csharp/latest/workspace/reference/libtmux-workspace-workspaceaction-request/
[workspaceactionkind-createsession]: https://libtmux.org/en/csharp/latest/workspace/reference/libtmux-workspace-workspaceactionkind-createsession/
[workspaceactionkind-captureresult]: https://libtmux.org/en/csharp/latest/workspace/reference/libtmux-workspace-workspaceactionkind-captureresult/
[mcp-list_sessions]: https://libtmux.org/en/csharp/latest/mcp/tools/list_sessions/
[mcp-list_windows]: https://libtmux.org/en/csharp/latest/mcp/tools/list_windows/
[mcp-list_panes]: https://libtmux.org/en/csharp/latest/mcp/tools/list_panes/
[mcp-capture_pane]: https://libtmux.org/en/csharp/latest/mcp/tools/capture_pane/
[mcp-snapshot_pane]: https://libtmux.org/en/csharp/latest/mcp/tools/snapshot_pane/
[mcp-wait_for_text]: https://libtmux.org/en/csharp/latest/mcp/tools/wait_for_text/
[mcp-capabilities]: https://libtmux.org/en/csharp/latest/mcp/resources/tmux_capabilities/
