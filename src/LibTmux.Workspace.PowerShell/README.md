# LibTmux.Workspace

The workspace module of
[libtmux for PowerShell](https://github.com/libtmux/libtmux-powershell#readme).
Describe a tmux session in YAML or JSON, review the plan, then apply it. The
module needs the matching [`LibTmux`](https://github.com/libtmux/libtmux-powershell/tree/master/src/LibTmux.PowerShell)
core module, and installing it also installs that dependency.

Reference: [every cmdlet][module], the
[workspace guide](https://libtmux.org/en/powershell/latest/workspace/source-guide/)
and the [PowerShell Gallery page](https://www.powershellgallery.com/packages/LibTmux.Workspace).

## Install

Use PowerShell 7.4 or later with tmux on the same Linux host:

```console
$ Install-PSResource -Name LibTmux.Workspace `
    -Version 0.1.0-alpha2 `
    -Prerelease `
    -Repository PSGallery `
    -Scope CurrentUser `
    -TrustRepository
```

Import both modules by their numeric version:

```console
$ Import-Module -Name LibTmux, LibTmux.Workspace `
    -RequiredVersion 0.1.0 `
    -ErrorAction Stop
```

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

## Load, review and apply

Create a handle for a private socket with
[`New-TmuxServer`][new-tmuxserver]. It does not contact tmux:

<!-- example: read.endpoint -->
```powershell
$server = LibTmux\New-TmuxServer `
    -SocketName ('libtmux-readme-' + [Guid]::NewGuid().ToString('N')) `
    -ConfigurationFile /dev/null
```

Describe a two-pane workspace. Importing it parses YAML without running its
commands:

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

Plan on the private endpoint. Planning may read tmux state; it does not create
the workspace:

<!-- example: readme.workspace.02-plan -->
```powershell
$workspacePlan = $workspace | LibTmux.Workspace\Get-TmuxWorkspacePlan `
    -Server $server -ServerStartup CreateOrJoin -ExistingSession Error
```

Preview without applying the plan:

<!-- example: readme.workspace.04-preview -->
```powershell
$workspacePlan | LibTmux.Workspace\Invoke-TmuxWorkspace -WhatIf
```

Apply that exact plan, then remove only the session it created. The result is a
native [`LibTmux.Workspace.WorkspaceResult`][workspaceresult]; it stays readable
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

`$workspaceResult.Windows` holds `editor` with two panes. The blocks above are
copies of tested sources: the
[guide test](https://github.com/libtmux/libtmux-powershell/blob/master/tests/GuideExamples.Tests.ps1)
fails when a copy drifts, and the
[installed workflow test](https://github.com/libtmux/libtmux-powershell/blob/master/tests/ReadmeWorkflow.Tests.ps1)
applies the workspace on an owned tmux server.

The [workspace guide](https://github.com/libtmux/libtmux-powershell/blob/master/docs/workspace.md)
covers failure recovery, attaching and exporting a declaration.

[module]: https://libtmux.org/en/powershell/latest/workspace/reference/
[new-tmuxserver]: https://libtmux.org/en/powershell/latest/reference/libtmux-new-tmuxserver/
[get-tmuxworkspace]: https://libtmux.org/en/powershell/latest/workspace/reference/libtmux-workspace-get-tmuxworkspace/
[import-tmuxworkspace]: https://libtmux.org/en/powershell/latest/workspace/reference/libtmux-workspace-import-tmuxworkspace/
[resolve-tmuxworkspace]: https://libtmux.org/en/powershell/latest/workspace/reference/libtmux-workspace-resolve-tmuxworkspace/
[test-tmuxworkspace]: https://libtmux.org/en/powershell/latest/workspace/reference/libtmux-workspace-test-tmuxworkspace/
[get-tmuxworkspaceplan]: https://libtmux.org/en/powershell/latest/workspace/reference/libtmux-workspace-get-tmuxworkspaceplan/
[invoke-tmuxworkspace]: https://libtmux.org/en/powershell/latest/workspace/reference/libtmux-workspace-invoke-tmuxworkspace/
[convertto-tmuxworkspace]: https://libtmux.org/en/powershell/latest/workspace/reference/libtmux-workspace-convertto-tmuxworkspace/
[workspaceresult]: https://libtmux.org/en/csharp/latest/workspace/reference/libtmux-workspace-workspaceresult/
