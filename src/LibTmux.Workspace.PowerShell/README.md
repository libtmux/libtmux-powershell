<!-- libtmux-logo -->
<div align="center">
  <picture>
    <source srcset="assets/logo.svg" type="image/svg+xml">
    <img src="assets/logo.png" width="128" height="128" alt="libtmux for PowerShell workspace">
  </picture>
</div>
<!-- /libtmux-logo -->

<div align="center">

# LibTmux.Workspace

The workspace module of
[libtmux for PowerShell](https://github.com/libtmux/libtmux-powershell#readme).
Describe a tmux session in YAML or JSON, review the plan, then apply it. The
module needs the matching [`LibTmux`](https://github.com/libtmux/libtmux-powershell/tree/master/src/LibTmux.PowerShell)
core module, and installing it also installs that dependency.

</div>

Reference: [every cmdlet][module], the
[workspace guide](https://libtmux.org/en/powershell/latest/workspace/source-guide/)
and the [PowerShell Gallery page](https://www.powershellgallery.com/packages/LibTmux.Workspace).

**Contents** — [Quick start](#quick-start) · [Commands](#commands) ·
[Leaves out](#what-it-leaves-out) · [Support](#support-and-status)

## Quick start

Install the module on PowerShell 7.4 or later, with tmux on the same Linux
host, including WSL:

```console
$ Install-PSResource -Name LibTmux.Workspace
```

Import both modules:

```console
$ Import-Module -Name LibTmux, LibTmux.Workspace -ErrorAction Stop
```

### [`New-TmuxServer`][new-tmuxserver]: a handle on a private server

It creates a handle for a private socket and an empty tmux configuration. It
contacts nothing, so your default server stays untouched:

<!-- example: read.endpoint -->
```powershell
$server = LibTmux\New-TmuxServer `
    -SocketName ('libtmux-readme-' + [Guid]::NewGuid().ToString('N')) `
    -ConfigurationFile /dev/null
```

### [`Import-TmuxWorkspace`][import-tmuxworkspace]: read a declaration

It parses YAML or JSON without contacting tmux or running the commands in it.
This declaration has two panes in one window:

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

It plans on the private endpoint. Planning may read tmux state and creates
nothing:

<!-- example: readme.workspace.02-plan -->
```powershell
$workspacePlan = $workspace | LibTmux.Workspace\Get-TmuxWorkspacePlan `
    -Server $server -ServerStartup CreateOrJoin -ExistingSession Error
```

### [`Invoke-TmuxWorkspace`][invoke-tmuxworkspace]: preview, then apply

`-WhatIf` previews the plan without applying it:

<!-- example: readme.workspace.04-preview -->
```powershell
$workspacePlan | LibTmux.Workspace\Invoke-TmuxWorkspace -WhatIf
```

It prints a `What if:` line followed by the plan's actions. Apply that exact
plan, then remove only the session it created. The result is a
[`LibTmux.Workspace.WorkspaceResult`][workspaceresult], and it stays readable
after cleanup:

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

`$workspaceResult.Windows` holds `editor` with two panes.

The blocks above are copies of tested sources. The
[guide test](https://github.com/libtmux/libtmux-powershell/blob/master/tests/GuideExamples.Tests.ps1)
fails when a copy drifts, and the
[installed workflow test](https://github.com/libtmux/libtmux-powershell/blob/master/tests/ReadmeWorkflow.Tests.ps1)
applies the workspace on an owned tmux server.

## Commands

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

The [workspace guide](https://github.com/libtmux/libtmux-powershell/blob/master/docs/workspace.md)
covers failure recovery, attaching and exporting a declaration.

## What it leaves out

- **Host scripts by default.** A declaration's `before_script` runs only when
  planning admits it with `-AllowHostScripts`. Validation, planning and
  `-WhatIf` never run it.
- **Readiness inference.** The default `-Readiness Immediate` sends configured
  commands as literal input and does not infer shell readiness or completion.
- **Partial success objects.** A failed apply writes an error that carries the
  journal and any partial result, and emits no success object.

The [workspace guide](https://github.com/libtmux/libtmux-powershell/blob/master/docs/workspace.md#startup-host-effects-and-failures)
holds the full rules.

## Support and status

- **Releases.** Releases are numbered `0.1.N`, and each release increments `N`.
  The API is not settled: any release may change or remove exported
  identifiers, and the changelog marks each break. Pin an exact version to
  avoid one.
- **Versions.** Install both modules at the same version.
- **PowerShell and tmux.** PowerShell 7.4 or later and tmux 3.3a or newer. CI
  runs PowerShell 7.4.20 and 7.6.6 with tmux 3.3a through 3.8 and master.
- **Systems.** Linux, including WSL: run PowerShell and tmux in the same Linux
  environment. CI runs Linux x64 on every change and macOS as an advisory trial
  whose failures never fail the check. CI has no Windows job.

[module]: https://libtmux.org/en/powershell/latest/workspace/reference/
[new-tmuxserver]: https://libtmux.org/en/powershell/latest/reference/libtmux-new-tmuxserver/
[get-tmuxworkspace]: https://libtmux.org/en/powershell/latest/workspace/reference/libtmux-workspace-get-tmuxworkspace/
[import-tmuxworkspace]: https://libtmux.org/en/powershell/latest/workspace/reference/libtmux-workspace-import-tmuxworkspace/
[resolve-tmuxworkspace]: https://libtmux.org/en/powershell/latest/workspace/reference/libtmux-workspace-resolve-tmuxworkspace/
[test-tmuxworkspace]: https://libtmux.org/en/powershell/latest/workspace/reference/libtmux-workspace-test-tmuxworkspace/
[get-tmuxworkspaceplan]: https://libtmux.org/en/powershell/latest/workspace/reference/libtmux-workspace-get-tmuxworkspaceplan/
[invoke-tmuxworkspace]: https://libtmux.org/en/powershell/latest/workspace/reference/libtmux-workspace-invoke-tmuxworkspace/
[convertto-tmuxworkspace]: https://libtmux.org/en/powershell/latest/workspace/reference/libtmux-workspace-convertto-tmuxworkspace/
[workspacefile]: https://libtmux.org/en/csharp/latest/workspace/reference/libtmux-workspace-workspacefile/
[workspaceresult]: https://libtmux.org/en/csharp/latest/workspace/reference/libtmux-workspace-workspaceresult/
