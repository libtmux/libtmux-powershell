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

[![LibTmux](https://img.shields.io/powershellgallery/v/LibTmux?label=LibTmux)](https://www.powershellgallery.com/packages/LibTmux)
[![libtmux.org](https://img.shields.io/badge/docs-libtmux.org-0b7285)](https://libtmux.org/en/powershell/)

The core module of
[libtmux for PowerShell](https://github.com/libtmux/libtmux-powershell#readme).
Create, read, arrange and remove tmux [sessions][session], [windows][window]
and [panes][pane], send input and capture output as native objects.

</div>

Reference: [every cmdlet][module],
[getting started](https://libtmux.org/en/powershell/latest/guides/getting-started/),
[PowerShell Gallery](https://www.powershellgallery.com/packages/LibTmux).

**Contents** — [Quick start](#quick-start) · [Find a cmdlet](#find-a-cmdlet) ·
[Leaves out](#what-it-leaves-out) · [Support](#support-and-status)

## Quick start

Install the module with `pwsh` 7.4 or newer and tmux 3.3a or newer, on Linux
or WSL:

```console
$ Install-PSResource -Name LibTmux
```

Import it:

```console
$ Import-Module -Name LibTmux -ErrorAction Stop
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

More: [send input][guide-input]. Some cmdlets need a newer tmux:
[optional features][guide-compatibility].

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
walks through each of these. The
[workspace module](https://github.com/libtmux/libtmux-powershell/tree/master/src/LibTmux.Workspace.PowerShell)
builds sessions from YAML or JSON.

## What it leaves out

- **Live objects.** A captured object keeps what tmux said when you read it.
  [`Get-TmuxSnapshot`][get-tmuxsnapshot] reads again; the
  [read guide][guide-read] lists what a capture cannot know.
- **An implicit server.** A handle from [`New-TmuxServer`][new-tmuxserver]
  starts no daemon, and importing the module connects to none. `TMUX` and
  `TMUX_PANE` stay as they are ([compatibility][guide-compatibility]).
- **Shell quoting.** [`Send-TmuxText`][send-tmuxtext] sends its text literally;
  quote it for the receiving shell yourself ([send input][guide-input]).

## Support and status

- **Pre-1.0.** Any release may change or remove exported identifiers; the
  changelog marks breaks. Pin an exact version.
- **PowerShell.** 7.4 or newer. Windows PowerShell 5.1 cannot load the module.
- **tmux.** 3.3a or newer. Some cmdlets need more:
  [optional features][guide-compatibility].
- **Systems.** Linux and WSL, with PowerShell and tmux in the same Linux
  environment.
- **Changelog.** [What each release of `LibTmux` changed][changelog]; the
  [main changelog][changelog-main] holds what spans both modules.

[changelog]: https://github.com/libtmux/libtmux-powershell/blob/master/module/LibTmux/CHANGELOG.md
[changelog-main]: https://github.com/libtmux/libtmux-powershell/blob/master/CHANGELOG.md
[module]: https://libtmux.org/en/powershell/latest/reference/
[guide-read]: https://libtmux.org/en/powershell/latest/guides/read/
[guide-input]: https://libtmux.org/en/powershell/latest/guides/input/
[guide-compatibility]: https://libtmux.org/en/powershell/latest/guides/compatibility/
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
[session]: https://libtmux.org/en/csharp/latest/reference/libtmux-session/
[window]: https://libtmux.org/en/csharp/latest/reference/libtmux-window/
[pane]: https://libtmux.org/en/csharp/latest/reference/libtmux-pane/
[panerunresult]: https://libtmux.org/en/csharp/latest/reference/libtmux-panerunresult/
