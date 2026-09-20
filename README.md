# libtmux for PowerShell

Create tmux sessions, split panes, send input and capture terminal output with
native PowerShell cmdlets. Read tmux into typed snapshots, then use
`Where-Object`, `Select-Object` and the rest of the pipeline without starting
another tmux process.

[Quick start](#create-a-session-and-split-a-pane) ·
[Read and filter](docs/read.md) · [Capture](docs/capture.md) ·
[Input](docs/input.md) · [Cmdlet help](docs/reference/LibTmux)

**Alpha.** APIs can change. The modules are available from this checkout;
they have not been published to PowerShell Gallery.

## Try from a checkout

Use PowerShell 7.4 or later with tmux installed on a Unix host. Install the
pinned development tools from the repository root:

```console
$ mise install
```

Build the modules and restore their pinned .NET dependencies:

```console
$ pwsh -NoLogo -NoProfile -File eng/Build.ps1 \
    -Restore
```

Open PowerShell with the built modules on its search path:

```console
$ PSModulePath="$PWD/build/Modules" pwsh -NoLogo -NoProfile
```

See [contributing](.github/CONTRIBUTING.md) for local packages and development
checks. The examples below run in that PowerShell session.

## Create a session and split a pane

Choose a socket explicitly. This constructs a `LibTmux.Server` handle; it
contacts tmux only when you use it in an operation.

<!-- example: read.endpoint -->
```powershell
$server = LibTmux\New-TmuxServer -SocketName development
```

Create a detached `demo` session with two panes, capture its state, and
remove the session in `finally`. Both panes run `cat` so they stay open
without depending on your shell configuration. An existing session named
`demo` causes an error; the example does not replace it.

<!-- example: readme.create -->
```powershell
$captured = & {
    $session = $server | New-TmuxSession -Name 'demo' -WindowName 'editor' -Command 'exec /bin/cat' -Width 100 -Height 30 -ErrorAction Stop
    try {
        $pane = $session | Get-TmuxPane -ErrorAction Stop
        $null = $pane | Split-TmuxPane -Horizontal -Size 40 -Command 'exec /bin/cat' -ErrorAction Stop
        $snapshot = $server | Get-TmuxSnapshot -ErrorAction Stop
        $snapshot.Sessions | Where-Object Name -CEQ 'demo'
    } finally {
        $session | Remove-TmuxSession -Confirm:$false -ErrorAction Stop
    }
}
```

`$captured` is a native `LibTmux.Session` with one window and two panes.
Its captured properties remain readable after cleanup. The server handle
borrows the endpoint: removing this session leaves any other sessions alone.

Filter the captured panes locally, even after the session has been removed:

<!-- example: readme.filter -->
```powershell
$captured.Panes | Where-Object Width -GE 50 | Select-Object Id, Width, Height
```

This selects the wider pane, with width 59 and height 30. Its typed ID depends
on the server. Property access, formatting and this pipeline perform no tmux
I/O. Acquire another snapshot with `Get-TmuxSnapshot` when you need fresh
state. See [read and filter](docs/read.md) for exact selectors, arrays and
linked windows.

## Send input and capture the result

Send literal text to a shell and use `-Enter` to submit it. The shell signals
a unique channel after printing, so capture waits for completed output. The
signal uses the endpoint's tmux executable, with its path quoted for the
shell. A successful send alone means tmux accepted the input; it does not
establish that the receiving program finished.

<!-- example: readme.input -->
```powershell
& {
    $ErrorActionPreference = 'Stop'
    $ready = 'libtmux-demo-' + [Guid]::NewGuid().ToString('N')
    $tmux = (Get-Command $server.ConnectionOptions.TmuxBinaryPath -CommandType Application).Source
    $signal = "'{0}' wait-for -S '{1}'" -f $tmux.Replace("'", "'\''"), $ready
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

The captured screen includes `hello from PowerShell`. `Wait-TmuxChannel`
accepts a signal that arrived before the wait, reports a timeout if no signal
arrives, and withdraws its waiter on timeout or Ctrl+C. Use one waiter per
unique channel: tmux withdrawal also wakes other waiters on that channel.
The example removes its `input-demo` session in `finally`.
`Send-TmuxKey` sends key tokens such as `C-c` or `Enter`; `Send-TmuxText`
sends those characters literally. Mutation commands also support `-WhatIf`
and `-Confirm`. See [input](docs/input.md) and [capture](docs/capture.md).

## Workspaces and MCP

The separate `LibTmux.Workspace` module parses workspace YAML into a native
`LibTmux.Workspace.WorkspaceFile` without running its commands:

<!-- example: workspace.parse -->
```powershell
LibTmux.Workspace\Import-TmuxWorkspace -Yaml 'session_name: development'
```

Workspace parsing is available; workspace planning and application are under
development. Install both modules at the same version. For an assistant that
drives tmux, use the separately packaged
[LibTmux.Mcp tool](https://github.com/libtmux/libtmux-dotnet/tree/master/src/LibTmux.Mcp).

## Guides

- [Arrange panes and resize windows](docs/layout.md): layouts, dimensions and
  zoom toggling.
- [Watch events and use runspaces](docs/watch.md): bounded event delivery,
  thread jobs and independent concurrent clients.
- [Compose commands and reuse control clients](docs/commands.md): ordered
  chains, native replies and explicit connection cleanup.
- [Inspect attached clients](docs/clients.md): captured state and current
  attachment.
- [Create sessions, windows and panes](docs/create.md): owners, sizing,
  commands and environment entries.
- [Remove sessions, windows and panes](docs/remove.md): confirmation and
  shared-window effects.
- [Read objects and snapshots](docs/read.md): typed pipelines, exact selection
  and captured relationships.
- [Capture and raw commands](docs/capture.md): scrollback, rendered text and
  tmux commands without a dedicated cmdlet.
- [Send input](docs/input.md): literal text, keys and partial failure.
- [Read and change options](docs/options.md): scoped tables, inheritance and
  indexed values.
- [Configure and run hooks](docs/hooks.md): indexed commands and explicit
  invocation.
- [Set the environment for new panes](docs/environment.md): local overrides,
  empty values and removal markers.
