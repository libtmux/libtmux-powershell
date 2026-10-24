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
Its cmdlets create, read, arrange and remove tmux [sessions][session],
[windows][window] and [panes][pane], send input and capture output as native
objects.

</div>

Reference: [every cmdlet][module], the
[getting started guide](https://libtmux.org/en/powershell/latest/guides/getting-started/)
and the [PowerShell Gallery page](https://www.powershellgallery.com/packages/LibTmux).

**Contents** — [Quick start](#quick-start) · [Find a cmdlet](#find-a-cmdlet) ·
[Leaves out](#what-it-leaves-out) · [Support](#support-and-status)

## Quick start

Install the module on PowerShell 7.4 or later, with tmux on the same Linux
host, including WSL:

```console
$ Install-PSResource -Name LibTmux `
    -Version 0.1.0-alpha3 `
    -Prerelease `
    -Repository PSGallery `
    -Scope CurrentUser `
    -TrustRepository
```

Import it by its numeric version, `0.1.0`:

```console
$ Import-Module -Name LibTmux `
    -RequiredVersion 0.1.0 `
    -ErrorAction Stop
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

### [`Invoke-TmuxPaneCommand`][invoke-tmuxpanecommand]: a command's exit status

It runs a command in a pane and returns a
[`LibTmux.PaneRunResult`][panerunresult].
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

The blocks above are copies of tested sources. The
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

## What it leaves out

- **Live objects.** A captured object keeps what tmux reported when you read it.
  [`Get-TmuxSnapshot`][get-tmuxsnapshot] reads again, and the
  [read guide][guide-read] lists what a capture cannot know.
- **An implicit server.** A handle from [`New-TmuxServer`][new-tmuxserver]
  starts no daemon, and importing the module connects to none. The module
  leaves `TMUX` and `TMUX_PANE` in your session as they are
  ([compatibility][guide-compatibility]).
- **Shell quoting.** [`Send-TmuxText`][send-tmuxtext] sends its text literally
  and does not quote it for the shell that receives it
  ([send input][guide-input]).

## Support and status

- **Alpha.** Gallery packages carry a `0.1.0-alphaN` label and APIs may change,
  so pin an exact version. PowerShell imports use the numeric `0.1.0`.
- **PowerShell and tmux.** PowerShell 7.4 or later and tmux 3.3a or newer. CI
  runs PowerShell 7.4.20 and 7.6.6 with tmux 3.3a through 3.8 and master;
  [compatibility][guide-compatibility] holds the contract.
- **Systems.** Linux, including WSL: run PowerShell and tmux in the same Linux
  environment. CI runs Linux x64 on every change and macOS as an advisory trial
  whose failures never fail the check. CI has no Windows job.

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
