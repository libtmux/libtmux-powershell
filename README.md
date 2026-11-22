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
objects that a pipeline can filter.

</div>

Install [`LibTmux`](https://www.powershellgallery.com/packages/LibTmux/) from
the PowerShell Gallery with PowerShell 7.4 or newer and tmux 3.3a or newer on
Linux or WSL ([compatibility](docs/compatibility.md)):

```console
$ Install-Module -Name LibTmux
```

Or with `PSResourceGet`:

```console
$ Install-PSResource -Name LibTmux
```

For a source checkout, see [Install from source](#install-from-source) and
[CONTRIBUTING.md](.github/CONTRIBUTING.md#setup).

**Contents** — [Quick start](#quick-start) ·
[Find things](#find-sessions-windows-and-panes) ·
[Panes](#split-resize-type-into-and-read-panes) ·
[Service readiness](#wait-for-service-readiness) ·
[Choose how to run](#choose-how-to-run) ·
[Workspaces](#build-a-workspace-from-a-file) · [Packages](#packages) ·
[Leaves out](#what-it-leaves-out) · [Support](#support-and-status)

## Quick start

### [`New-TmuxServer`][new-tmuxserver]: a handle on a private server

It names a socket and an empty tmux configuration, and contacts nothing, so
your default server stays untouched:

<!-- example: read.endpoint -->
```powershell
Import-Module -Name LibTmux -ErrorAction Stop
$server = LibTmux\New-TmuxServer `
    -SocketName ('libtmux-readme-' + [Guid]::NewGuid().ToString('N')) `
    -ConfigurationFile /dev/null
```

Without a socket, tmux picks the server: the one in `TMUX` inside a pane,
otherwise its default. `LIBTMUX_SOCKET_PATH` or `LIBTMUX_SOCKET` chooses one.
More: [read tmux objects](docs/read.md).

### [`Invoke-TmuxPaneCommand`][invoke-tmuxpanecommand]: run a command, read its exit status

It returns a [`LibTmux.PaneRunResult`][panerunresult] and needs tmux 3.4 or
newer. [`New-TmuxSession`][new-tmuxsession] starts the shell, and the `finally`
block removes only that session with [`Remove-TmuxSession`][remove-tmuxsession]:

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

It prints `ExitStatus = 7` and `TimedOut = False`. A nonzero exit status
raises no error. On timeout the command may still run and the result has no
exit status.

More: [command completion](docs/input.md#run-a-command-to-completion). Later
sections reuse `$server`.

### [`examples/QuickStart.ps1`](examples/QuickStart.ps1): a private server and three panes

Run it from a checkout root to start a private server, split `editor`, add
`logs`, stop the server, and return a captured [`LibTmux.Session`][session]:

<!-- example: readme.quickstart -->
```powershell
(./examples/QuickStart.ps1).Windows | Select-Object Name, @{
    Name = 'PaneIds'
    Expression = { $_.Panes.Id -join ', ' }
}
```

It prints:

```text
Name   PaneIds
----   -------
editor %0, %1
logs   %2
```

Its [`Windows`][session-windows] and [`Panes`][session-panes] stay readable
after cleanup, and your default tmux server stays untouched.

### Install from source

From a checkout with [mise](https://mise.jdx.dev/) tools installed
([setup](.github/CONTRIBUTING.md#setup)), restore the
[libtmux for .NET packages](https://www.nuget.org/packages/LibTmux) and build
both modules into `build/Modules`:

```console
$ pwsh -NoLogo -NoProfile -File eng/Build.ps1 \
    -Restore
```

Start PowerShell with the staged module path (see
[review package builds](.github/CONTRIBUTING.md#review-package-builds) for
shared .NET changes):

```console
$ LIBTMUX_REVIEW_MODULE_ROOT="$PWD/build/Modules" \
    pwsh \
    -NoLogo \
    -NoProfile
```

Import the staged manifests so an installed module cannot shadow the build:

<!-- example: readme.install.import -->
```powershell
$modules = $env:LIBTMUX_REVIEW_MODULE_ROOT
Import-Module -Name @(
    "$modules/LibTmux/0.1.0/LibTmux.psd1",
    "$modules/LibTmux.Workspace/0.1.0/LibTmux.Workspace.psd1"
) -ErrorAction Stop
```

## Find sessions, windows, and panes

### [`Get-TmuxSnapshot`][get-tmuxsnapshot]: what tmux holds, in one read

One call returns every session, window and pane as native objects. This
example builds a tree with [`New-TmuxSession`][new-tmuxsession],
[`Split-TmuxPane`][split-tmuxpane] and [`New-TmuxWindow`][new-tmuxwindow], reads
it, and removes it. `cat` keeps the panes open:

<!-- example: readme.create -->
```powershell
Import-Module -Name LibTmux -ErrorAction Stop
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
objects, and their [`Panes`][window-panes] hold [`LibTmux.Pane`][pane] objects:

| Expression | Captured result |
| --- | --- |
| `$captured` | A `Session` named `demo` |
| [`$captured.Windows`][session-windows] | Two `Window` objects: `editor` and `logs` |
| [`$captured.Windows[0].Panes`][window-panes] | Two `Pane` objects in `editor`; `logs` has one |

A captured object keeps what tmux said when you read it. Call
[`Get-TmuxSnapshot`][get-tmuxsnapshot] again to see a later change.

More: [snapshots and linked windows](docs/read.md).

### Filter the captured graph

`Where-Object` reads the capture and starts no tmux client:

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

Criteria select the one window with two or more panes; `-ExactlyOne` fails on
zero or several matches. It starts no tmux client either:

<!-- example: readme.related -->
```powershell
$captured.Windows |
    Select-TmuxWindow -Criteria @{ 'Panes.Count' = @{ Ge = 2 } } -ExactlyOne
```

It returns `editor`, the same object as `$captured.Windows[0]`.

More: [filter and query](docs/query.md).

### [`Get-TmuxQueryPlan`][get-tmuxqueryplan]: see what runs in tmux

[`New-TmuxQuery`][new-tmuxquery] builds criteria once. A plan shows which part
tmux evaluates and which part runs in PowerShell, and reads nothing:

<!-- example: readme.plan -->
```powershell
$query = New-TmuxQuery -Target Window -Criteria ([ordered]@{
    IsActive = $true
    Name = 'editor'
})
$plan = $query | Get-TmuxQueryPlan -DaemonVersion '3.6'
'in tmux: {0}; here: {1}' -f
    ($null -ne $plan.PushedPredicate), ($null -ne $plan.ResidualPredicate)
```

It prints `in tmux: True; here: True`: tmux evaluates `IsActive` and PowerShell
evaluates `Name`. The split depends on the tmux release the plan names.
`-Pushdown Never` keeps everything local, and `Require` fails if any part must
stay local.

[`Invoke-TmuxQuery`][invoke-tmuxquery] runs the query against a server and
returns fresh objects:

<!-- example: readme.query -->
```powershell
& {
    $ErrorActionPreference = 'Stop'
    $session = $server |
        New-TmuxSession -Name query -WindowName editor -Command 'exec /bin/cat'
    try {
        $server | Invoke-TmuxQuery -Query $query | ForEach-Object Name
    } finally {
        $session | Remove-TmuxSession -Confirm:$false
    }
}
```

It prints `editor`.

More: [store a query or acquire a fresh result](docs/query.md#store-a-query-or-acquire-a-fresh-result).

### [`Update-TmuxPane`][update-tmuxpane]: read a held pane again

It returns a fresh copy of a held [`Pane`][pane] and leaves the original as it
was. This example retitles a pane with
[`Invoke-TmuxCommand`][invoke-tmuxcommand] after `$held` was read:

<!-- example: readme.refresh -->
```powershell
& {
    $ErrorActionPreference = 'Stop'
    $session = $server |
        New-TmuxSession -Name refresh -Command 'exec /bin/cat'
    try {
        $id = ($session | Get-TmuxPane).Id.ToString()
        $retitle = { param($text)
            $null = $server | Invoke-TmuxCommand -Confirm:$false `
                -Arguments 'select-pane', '-t', $id, '-T', $text
        }
        & $retitle editor
        $held = $session | Get-TmuxPane
        & $retitle build
        $fresh = $held | Update-TmuxPane
        '{0} {1}' -f $held.Title, $fresh.Title
    } finally {
        $session | Remove-TmuxSession -Confirm:$false
    }
}
```

It prints `editor build`. For a session or window, read again with
[`Get-TmuxSession`][get-tmuxsession] or [`Get-TmuxWindow`][get-tmuxwindow].

## Split, resize, type into and read panes

### [`Split-TmuxPane`][split-tmuxpane]: add a pane and work in it

[`Send-TmuxText`][send-tmuxtext] and [`Send-TmuxKey`][send-tmuxkey] type into
a pane, and [`Get-TmuxPaneContent`][get-tmuxpanecontent] reads its screen.

[`Set-TmuxWindowSize`][set-tmuxwindowsize] and
[`Set-TmuxPaneSize`][set-tmuxpanesize] resize. `cat` echoes what it receives,
and [`Wait-TmuxPaneText`][wait-tmuxpanetext] waits for the echo:

<!-- example: readme.panes -->
```powershell
Import-Module -Name LibTmux -ErrorAction Stop
& {
    $ErrorActionPreference = 'Stop'
    $session = $server | New-TmuxSession -Name panes -Command 'exec /bin/cat'
    try {
        $session | Get-TmuxWindow | Set-TmuxWindowSize -Width 100 -Height 30
        $left = $session | Get-TmuxPane
        $right = $left | Split-TmuxPane -Horizontal -Command 'exec /bin/cat'
        $right | Send-TmuxText -Text hello
        $right | Send-TmuxKey -Key Enter
        $null = $right | Wait-TmuxPaneText -Pattern '^hello$' -Timeout 10
        $right | Get-TmuxPaneContent | Select-Object -First 1
        ($left | Set-TmuxPaneSize -Width 30 -PassThru).Width
    } finally {
        $session | Remove-TmuxSession -Confirm:$false
    }
}
```

It prints `hello`, the first screen line, then `30`, the left pane's width.

More: [send text and keys](docs/input.md), [pane contents](docs/capture.md)
and [arrange and resize](docs/layout.md).

## Wait for service readiness

### [`Wait-TmuxPaneText`][wait-tmuxpanetext]: wait for a readiness line

It watches a pane's text and returns a
[`LibTmux.PaneWaitResult`][panewaitresult]. It uses a control client on tmux 3.7
or newer and polls on older releases.

[`Send-TmuxText`][send-tmuxtext] and [`Send-TmuxKey`][send-tmuxkey] type into
the pane first, and [`Get-TmuxPaneContent`][get-tmuxpanecontent] reads its
screen. If the application can signal completion itself, use
[`Wait-TmuxChannel`][wait-tmuxchannel] with
[a channel](docs/input.md#send-a-command-and-wait-for-its-output).

With Python 3 on `PATH`, this example starts an HTTP server on a free loopback
port, waits for its readiness line, then requests a page:

<!-- example: input.http-ready -->
```powershell
Import-Module -Name LibTmux -ErrorAction Stop
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

It prints the wait result, outcome `PresentAtEntry` or `Matched`, then HTTP
status 200.

More: [pane-text waits](docs/input.md#wait-for-an-applications-readiness-line).

## Choose how to run

Pick a mode by who owns the client and how failures are reported:

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

A cmdlet refuses before it changes anything when tmux is too old:

- **tmux 3.4:** [`Invoke-TmuxPaneCommand`][invoke-tmuxpanecommand].
- **tmux 3.7:** [`Connect-TmuxControl`][connect-tmuxcontrol] and
  [`Watch-TmuxEvent`][watch-tmuxevent] with a server.

[Optional features](docs/compatibility.md#optional-features) lists every
refusal, and [`capabilities.json`](capabilities.json) holds the list for a
script to read.

The raw-command cmdlets [`Invoke-TmuxCommand`][invoke-tmuxcommand],
[`Invoke-TmuxChain`][invoke-tmuxchain] and
[`Invoke-TmuxControlCommand`][invoke-tmuxcontrolcommand] check the command
they are given, not strings nested in it (`if-shell`, `bind-key`, braces).
[What the checks do not read](docs/compatibility.md#what-the-checks-do-not-read)
lists the rest.

### [`Invoke-TmuxChain`][invoke-tmuxchain]: several commands, one tmux call

[`New-TmuxCommand`][new-tmuxcommand] builds each command with literal
arguments. A chain runs them in order and stops at the first failure; earlier
changes stay. This example renames a window and reads the new name:

<!-- example: readme.chain -->
```powershell
& {
    $ErrorActionPreference = 'Stop'
    $session = $server |
        New-TmuxSession -Name chain -Command 'exec /bin/cat'
    try {
        $rename = New-TmuxCommand -Name rename-window -Arguments @(
            '-t', 'chain:0', 'build'
        )
        $show = New-TmuxCommand -Name display-message -Arguments @(
            '-p', '-t', 'chain:0', '#{window_name}'
        )
        $result = $server | Invoke-TmuxChain -Command @($rename, $show)
        $result.StandardOutputLines
    } finally {
        $session | Remove-TmuxSession -Confirm:$false
    }
}
```

It prints `build`.

More: [execute an ordered chain](docs/commands.md#execute-an-ordered-chain).

### [`Connect-TmuxControl`][connect-tmuxcontrol]: one client for repeated commands

It attaches one control client.
[`Invoke-TmuxControlCommand`][invoke-tmuxcontrolcommand] sends a command
through it, and [`Disconnect-TmuxControl`][disconnect-tmuxcontrol] ends it.
This example reads a session name, then disconnects and removes its session:

<!-- example: readme.control -->
```powershell
Import-Module -Name LibTmux -ErrorAction Stop
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

The reply is `control-demo`. The client stays connected for every command in
the inner `try` block.

More: [reuse a control client](docs/commands.md#reuse-a-control-client).

### [`Watch-TmuxEvent`][watch-tmuxevent]: react to notifications

It streams tmux notifications and pane output from a control client, with
event-count and text-byte limits. A server handle needs tmux 3.7 or newer.

More: [observe one owned change](docs/watch.md#observe-one-owned-change), a
complete program that starts its own server and cleans up.

The other modes:

- [`Enter-TmuxSession`][enter-tmuxsession] attaches your terminal to a session.
- Foreground cmdlets and `ForEach-Object -Parallel` occupy their pipeline.
- Thread jobs return the prompt while they run.

More: [commands and control clients](docs/commands.md).

## Build a workspace from a file

Describe a session once in YAML or JSON, review the plan, then apply it.
Installing the workspace module also installs `LibTmux`:

```console
$ Install-PSResource -Name LibTmux.Workspace
```

Import both modules:

```console
$ Import-Module -Name LibTmux, LibTmux.Workspace -ErrorAction Stop
```

### [`Import-TmuxWorkspace`][import-tmuxworkspace]: read a declaration

It parses YAML or JSON without contacting tmux or running its commands.
[`Get-TmuxWorkspace`][get-tmuxworkspace] finds declaration files,
[`Resolve-TmuxWorkspace`][resolve-tmuxworkspace] expands directories and
[`Test-TmuxWorkspace`][test-tmuxworkspace] validates one. This declaration has
two panes in one window:

<!-- example: readme.workspace.01-import -->
```powershell
Import-Module -Name LibTmux, LibTmux.Workspace -ErrorAction Stop
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

It plans against the same private server. Planning may read tmux and creates
nothing:

<!-- example: readme.workspace.02-plan -->
```powershell
$workspacePlan = $workspace | LibTmux.Workspace\Get-TmuxWorkspacePlan `
    -Server $server -ServerStartup CreateOrJoin -ExistingSession Error
```

Review the actions. The default view hides command text, option values, paths
and environment values; read an action's
[`Request`][workspaceaction-request] only in a trusted terminal:

<!-- example: readme.workspace.03-review -->
```powershell
$workspacePlan.Actions
```

It lists the actions in order, from
[`CreateSession`][workspaceactionkind-createsession] to
[`CaptureResult`][workspaceactionkind-captureresult], with `[redacted]` for
command text.

### [`Invoke-TmuxWorkspace`][invoke-tmuxworkspace]: preview, then apply

`-WhatIf` previews the plan without applying it:

<!-- example: readme.workspace.04-preview -->
```powershell
$workspacePlan | LibTmux.Workspace\Invoke-TmuxWorkspace -WhatIf
```

It prints a `What if:` line and the plan's actions. Apply that plan, then remove
only the session it created. The result stays readable after cleanup:

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

It returns `editor` with two panes.
[`ConvertTo-TmuxWorkspace`][convertto-tmuxworkspace] turns a captured session
into a starting declaration.

More: [apply the reviewed plan](docs/workspace.md#apply-the-reviewed-plan).

## Packages

| Product | Use it for |
| --- | --- |
| [LibTmux](docs/reference/README.md) | Typed cmdlets, snapshots, input, capture, control clients and event streams |
| [LibTmux.Workspace](docs/workspace.md#plan-and-review) [![LibTmux.Workspace](https://img.shields.io/powershellgallery/v/LibTmux.Workspace?label=LibTmux.Workspace)](https://www.powershellgallery.com/packages/LibTmux.Workspace) | Discover YAML/JSON declarations, resolve directories, review plans and create workspaces |

### [LibTmux](https://github.com/libtmux/libtmux-powershell/tree/master/src/LibTmux.PowerShell): typed cmdlets for tmux

Read, create, arrange and remove sessions, windows and panes, send input and
capture output as native objects.

Reference: [every LibTmux cmdlet][libtmux-module],
[PowerShell Gallery](https://www.powershellgallery.com/packages/LibTmux),
[changelog](module/LibTmux/CHANGELOG.md).

### [LibTmux.Workspace](https://github.com/libtmux/libtmux-powershell/tree/master/src/LibTmux.Workspace.PowerShell): workspaces from YAML or JSON

Describe a session once, review the plan, then apply it.
[Install it](#build-a-workspace-from-a-file) at the same version as `LibTmux`.

Reference: [every LibTmux.Workspace cmdlet][workspace-module],
[PowerShell Gallery](https://www.powershellgallery.com/packages/LibTmux.Workspace),
[changelog](module/LibTmux.Workspace/CHANGELOG.md).

## What it leaves out

- **Live objects.** A captured object keeps what tmux said when you read it.
  [`Get-TmuxSnapshot`][get-tmuxsnapshot] reads again; [snapshots and linked
  windows](docs/read.md) list what a capture cannot know.
- **An implicit server.** A handle from [`New-TmuxServer`][new-tmuxserver]
  starts no daemon, and importing the module connects to none. `TMUX` and
  `TMUX_PANE` stay as they are ([compatibility](docs/compatibility.md)).
- **Shell quoting.** [`Send-TmuxText`][send-tmuxtext] sends its text literally;
  quote it for the receiving shell yourself ([send input](docs/input.md)).
- **Native Windows.** Run PowerShell and tmux inside WSL. Native Windows and
  psmux are outside this port ([compatibility](docs/compatibility.md)).

## Support and status

- **Pre-1.0.** Any release may change or remove exported identifiers; each
  module's changelog marks breaks. Pin an exact version.
- **PowerShell.** 7.4 or newer. Windows PowerShell 5.1 cannot load the modules.
- **tmux.** 3.3a or newer. Some cmdlets need more: [optional
  features](docs/compatibility.md#optional-features).
- **Systems.** Linux and WSL, with PowerShell and tmux in the same Linux
  environment. macOS is a trial; [compatibility](docs/compatibility.md) has the
  detail.
- **Built on [libtmux for .NET](https://github.com/libtmux/libtmux-dotnet).**
  The cmdlets return its native objects and add parameter binding, help,
  formatting and `-WhatIf` / `-Confirm`.

[Documentation](https://libtmux.org/en/powershell/) ·
[Cmdlet reference](docs/reference/README.md) ·
[Compatibility](docs/compatibility.md) ·
[Troubleshooting](docs/troubleshooting.md) ·
[Benchmarks](benchmarks/README.md) ·
[Changelog](CHANGELOG.md) ·
[Contributing](.github/CONTRIBUTING.md) ·
[AI policy](https://libtmux.org/en/meta/ai-policy/)

Licensed under [MIT](LICENSE)
([third-party notices](licenses/THIRD-PARTY-NOTICES.md)). Part of the
[libtmux.org](https://libtmux.org/) family alongside
[Python libtmux](https://github.com/tmux-python/libtmux) and
[libtmux for .NET](https://github.com/libtmux/libtmux-dotnet).

[libtmux-module]: https://libtmux.org/en/powershell/latest/reference/
[workspace-module]: https://libtmux.org/en/powershell/latest/workspace/reference/
[new-tmuxserver]: https://libtmux.org/en/powershell/latest/reference/libtmux-new-tmuxserver/
[new-tmuxsession]: https://libtmux.org/en/powershell/latest/reference/libtmux-new-tmuxsession/
[split-tmuxpane]: https://libtmux.org/en/powershell/latest/reference/libtmux-split-tmuxpane/
[set-tmuxpanesize]: https://libtmux.org/en/powershell/latest/reference/libtmux-set-tmuxpanesize/
[set-tmuxwindowsize]: https://libtmux.org/en/powershell/latest/reference/libtmux-set-tmuxwindowsize/
[new-tmuxwindow]: https://libtmux.org/en/powershell/latest/reference/libtmux-new-tmuxwindow/
[get-tmuxsnapshot]: https://libtmux.org/en/powershell/latest/reference/libtmux-get-tmuxsnapshot/
[remove-tmuxsession]: https://libtmux.org/en/powershell/latest/reference/libtmux-remove-tmuxsession/
[select-tmuxwindow]: https://libtmux.org/en/powershell/latest/reference/libtmux-select-tmuxwindow/
[invoke-tmuxpanecommand]: https://libtmux.org/en/powershell/latest/reference/libtmux-invoke-tmuxpanecommand/
[wait-tmuxpanetext]: https://libtmux.org/en/powershell/latest/reference/libtmux-wait-tmuxpanetext/
[send-tmuxtext]: https://libtmux.org/en/powershell/latest/reference/libtmux-send-tmuxtext/
[send-tmuxkey]: https://libtmux.org/en/powershell/latest/reference/libtmux-send-tmuxkey/
[update-tmuxpane]: https://libtmux.org/en/powershell/latest/reference/libtmux-update-tmuxpane/
[get-tmuxsession]: https://libtmux.org/en/powershell/latest/reference/libtmux-get-tmuxsession/
[get-tmuxwindow]: https://libtmux.org/en/powershell/latest/reference/libtmux-get-tmuxwindow/
[get-tmuxpanecontent]: https://libtmux.org/en/powershell/latest/reference/libtmux-get-tmuxpanecontent/
[wait-tmuxchannel]: https://libtmux.org/en/powershell/latest/reference/libtmux-wait-tmuxchannel/
[connect-tmuxcontrol]: https://libtmux.org/en/powershell/latest/reference/libtmux-connect-tmuxcontrol/
[new-tmuxcommand]: https://libtmux.org/en/powershell/latest/reference/libtmux-new-tmuxcommand/
[invoke-tmuxcontrolcommand]: https://libtmux.org/en/powershell/latest/reference/libtmux-invoke-tmuxcontrolcommand/
[disconnect-tmuxcontrol]: https://libtmux.org/en/powershell/latest/reference/libtmux-disconnect-tmuxcontrol/
[invoke-tmuxchain]: https://libtmux.org/en/powershell/latest/reference/libtmux-invoke-tmuxchain/
[get-tmuxqueryplan]: https://libtmux.org/en/powershell/latest/reference/libtmux-get-tmuxqueryplan/
[new-tmuxquery]: https://libtmux.org/en/powershell/latest/reference/libtmux-new-tmuxquery/
[invoke-tmuxquery]: https://libtmux.org/en/powershell/latest/reference/libtmux-invoke-tmuxquery/
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
