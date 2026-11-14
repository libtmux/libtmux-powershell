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

[![LibTmux.Workspace](https://img.shields.io/powershellgallery/v/LibTmux.Workspace?label=LibTmux.Workspace)](https://www.powershellgallery.com/packages/LibTmux.Workspace)
[![libtmux.org](https://img.shields.io/badge/docs-libtmux.org-0b7285)](https://libtmux.org/en/powershell/latest/workspace/)

The workspace module of
[libtmux for PowerShell](https://github.com/libtmux/libtmux-powershell#readme).
Describe a tmux session in YAML or JSON, review the plan, then apply it. It
needs the [`LibTmux`](https://github.com/libtmux/libtmux-powershell/tree/master/src/LibTmux.PowerShell)
core module, and installing it installs that too.

</div>

Reference: [every cmdlet][module],
[workspace guide](https://libtmux.org/en/powershell/latest/workspace/source-guide/),
[PowerShell Gallery](https://www.powershellgallery.com/packages/LibTmux.Workspace).

**Contents** — [Quick start](#quick-start) · [Commands](#commands) ·
[Leaves out](#what-it-leaves-out) · [Support](#support-and-status)

## Quick start

Install the module with `pwsh` 7.4 or newer and tmux 3.3a or newer, on Linux
or WSL:

```console
$ Install-PSResource -Name LibTmux.Workspace
```

Import both modules:

```console
$ Import-Module -Name LibTmux, LibTmux.Workspace -ErrorAction Stop
```

### [`New-TmuxServer`][new-tmuxserver]: a handle on a private server

It names a socket and an empty tmux configuration, and contacts nothing, so
your default server stays untouched:

<!-- example: read.endpoint -->
```powershell
$server = LibTmux\New-TmuxServer `
    -SocketName ('libtmux-readme-' + [Guid]::NewGuid().ToString('N')) `
    -ConfigurationFile /dev/null
```

### [`Import-TmuxWorkspace`][import-tmuxworkspace]: read a declaration

It parses YAML or JSON without contacting tmux or running its commands. This
declaration has two panes in one window:

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

It plans against the private server. Planning may read tmux and creates
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

It prints a `What if:` line and the plan's actions. Apply that plan, then
remove only the session it created. The result is a
[`LibTmux.Workspace.WorkspaceResult`][workspaceresult] and stays readable after
cleanup:

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

More: the [workspace guide](https://github.com/libtmux/libtmux-powershell/blob/master/docs/workspace.md)
covers failure recovery, attaching and exporting.

## What it leaves out

- **Host scripts by default.** A declaration's `before_script` runs only with
  `-AllowHostScripts`. Validation, planning and `-WhatIf` never run it.
- **Readiness inference.** `-Readiness Immediate`, the default, sends commands
  as literal input and does not wait for the shell.
- **Partial success objects.** A failed apply writes an error that carries the
  journal and any partial result, and emits no success object.

More: [startup, host effects and failures](https://github.com/libtmux/libtmux-powershell/blob/master/docs/workspace.md#startup-host-effects-and-failures).

## Support and status

- **Pre-1.0.** Any release may change or remove exported identifiers; the
  changelog marks breaks. Pin an exact version.
- **Versions.** Install both modules at the same version.
- **PowerShell.** 7.4 or newer. Windows PowerShell 5.1 cannot load the module.
- **tmux.** 3.3a or newer.
- **Systems.** Linux and WSL, with PowerShell and tmux in the same Linux
  environment.
- **Changelog.** [What each release of `LibTmux.Workspace` changed][changelog];
  the [main changelog][changelog-main] holds what spans both modules.

[changelog]: https://github.com/libtmux/libtmux-powershell/blob/master/module/LibTmux.Workspace/CHANGELOG.md
[changelog-main]: https://github.com/libtmux/libtmux-powershell/blob/master/CHANGELOG.md
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
