<!-- libtmux-logo -->
<div align="center">
  <picture>
    <source srcset="assets/logo.svg" type="image/svg+xml">
    <img src="assets/logo.png" width="128" height="128" alt="libtmux for PowerShell">
  </picture>
</div>
<!-- /libtmux-logo -->

<div align="center">

# LibTmux

The core module of
[libtmux for PowerShell](https://github.com/libtmux/libtmux-powershell#readme).
Its cmdlets create, read, arrange and remove tmux sessions, windows and panes,
send input and capture output as native objects.

</div>

Reference: [every cmdlet][module], the
[getting started guide](https://libtmux.org/en/powershell/latest/guides/getting-started/)
and the [PowerShell Gallery page](https://www.powershellgallery.com/packages/LibTmux).

## Install

Use PowerShell 7.4 or later with tmux on the same Linux host:

```console
$ Install-PSResource -Name LibTmux `
    -Version 0.1.0-alpha2 `
    -Prerelease `
    -Repository PSGallery `
    -Scope CurrentUser `
    -TrustRepository
```

Import the module by its numeric version:

```console
$ Import-Module -Name LibTmux `
    -RequiredVersion 0.1.0 `
    -ErrorAction Stop
```

## Run a command and read its exit status

[`New-TmuxServer`][new-tmuxserver] creates a handle for a private socket
without contacting tmux:

<!-- example: read.endpoint -->
```powershell
$server = LibTmux\New-TmuxServer `
    -SocketName ('libtmux-readme-' + [Guid]::NewGuid().ToString('N')) `
    -ConfigurationFile /dev/null
```

[`Invoke-TmuxPaneCommand`][invoke-tmuxpanecommand] runs a command in a pane and
returns a native [`LibTmux.PaneRunResult`][panerunresult]. The `finally` block
removes only the session this example created, using
[`Remove-TmuxSession`][remove-tmuxsession]:

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
a result, not a tmux error. The blocks above are copies of tested sources: the
[guide test](https://github.com/libtmux/libtmux-powershell/blob/master/tests/GuideExamples.Tests.ps1)
fails when a copy drifts, and the
[installed workflow test](https://github.com/libtmux/libtmux-powershell/blob/master/tests/ReadmeWorkflow.Tests.ps1)
runs the same code on an owned tmux server.

## Find a cmdlet

- Read state with [`Get-TmuxSnapshot`][get-tmuxsnapshot] and filter it with
  [`Select-TmuxPane`][select-tmuxpane].
- Create with [`New-TmuxSession`][new-tmuxsession],
  [`New-TmuxWindow`][new-tmuxwindow] and [`Split-TmuxPane`][split-tmuxpane].
- Send input with [`Send-TmuxText`][send-tmuxtext]; read the screen with
  [`Get-TmuxPaneContent`][get-tmuxpanecontent].
- Wait for a readiness line with [`Wait-TmuxPaneText`][wait-tmuxpanetext].
- Reuse one control client with [`Connect-TmuxControl`][connect-tmuxcontrol] and
  watch events with [`Watch-TmuxEvent`][watch-tmuxevent].

The [repository README](https://github.com/libtmux/libtmux-powershell#readme)
walks through each of these, and the
[workspace module](https://github.com/libtmux/libtmux-powershell/tree/master/src/LibTmux.Workspace.PowerShell)
builds sessions from YAML or JSON declarations.

[module]: https://libtmux.org/en/powershell/latest/reference/
[new-tmuxserver]: https://libtmux.org/en/powershell/latest/reference/libtmux-new-tmuxserver/
[invoke-tmuxpanecommand]: https://libtmux.org/en/powershell/latest/reference/libtmux-invoke-tmuxpanecommand/
[remove-tmuxsession]: https://libtmux.org/en/powershell/latest/reference/libtmux-remove-tmuxsession/
[get-tmuxsnapshot]: https://libtmux.org/en/powershell/latest/reference/libtmux-get-tmuxsnapshot/
[select-tmuxpane]: https://libtmux.org/en/powershell/latest/reference/libtmux-select-tmuxpane/
[new-tmuxsession]: https://libtmux.org/en/powershell/latest/reference/libtmux-new-tmuxsession/
[new-tmuxwindow]: https://libtmux.org/en/powershell/latest/reference/libtmux-new-tmuxwindow/
[split-tmuxpane]: https://libtmux.org/en/powershell/latest/reference/libtmux-split-tmuxpane/
[send-tmuxtext]: https://libtmux.org/en/powershell/latest/reference/libtmux-send-tmuxtext/
[get-tmuxpanecontent]: https://libtmux.org/en/powershell/latest/reference/libtmux-get-tmuxpanecontent/
[wait-tmuxpanetext]: https://libtmux.org/en/powershell/latest/reference/libtmux-wait-tmuxpanetext/
[connect-tmuxcontrol]: https://libtmux.org/en/powershell/latest/reference/libtmux-connect-tmuxcontrol/
[watch-tmuxevent]: https://libtmux.org/en/powershell/latest/reference/libtmux-watch-tmuxevent/
[panerunresult]: https://libtmux.org/en/csharp/latest/reference/libtmux-panerunresult/
