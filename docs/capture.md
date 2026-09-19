# Capture, refresh and raw commands

`Get-TmuxPaneContent` reads rendered text from a native `LibTmux.Pane`.
`Update-TmuxPane` reads current pane metadata into a replacement handle.
Both accept a pane directly or through the pipeline and borrow its daemon.
`Invoke-TmuxCommand` accepts a native `LibTmux.Server` and literal tmux
arguments for operations that do not yet have a dedicated cmdlet.

Use the explicit endpoint and pane selection described in
[Read tmux objects](read.md). The examples below assume `$pane` and `$server`
refer to that selected pane and server. None chooses a global active server.

## Capture text

Return one string per captured screen line:

<!-- example: capture.lines -->
```powershell
$pane | Get-TmuxPaneContent
```

Capture the retained history as one string, joining wrapped screen lines:

<!-- example: capture.history -->
```powershell
$pane | Get-TmuxPaneContent -History -JoinWrappedLines -Raw
```

Capture an inclusive range, from ten lines before the visible screen through
its fifth line. Zero identifies the top visible line; negative values address
scrollback. Omitted bounds use tmux's normal visible-screen bounds.

<!-- example: capture.range -->
```powershell
$pane | Get-TmuxPaneContent -StartLine -10 -EndLine 4
```

`-History` selects the oldest retained history and cannot be combined with
`-StartLine`. It can be combined with `-EndLine`. `-Raw` emits exactly one
string per pane, joining the core's captured lines with LF and adding no
extra trailing newline. Internal empty lines remain empty lines. An empty
capture emits no objects normally and one empty string with `-Raw`.

This is rendered terminal text, not original process output or a byte-exact
stream. Sending input does not establish command completion: use a cooperative
wait channel or control event before asserting captured results.

| Switch | Effect |
| --- | --- |
| `JoinWrappedLines` | Join lines that wrapped on screen; tmux applies this in place of trailing-space handling. |
| `EscapeSequences` | Include terminal escape sequences representing captured attributes. |
| `EscapeNonPrintable` | Represent nonprintable bytes with octal escapes. |
| `PreserveTrailingSpaces` | Retain trailing spaces. |
| `TrimTrailingSpaces` | Request tmux's trailing-space trimming behavior. |
| `AlternateScreen` | Capture the alternate screen. |
| `Quiet` | Return empty content when an alternate screen is absent; other failures remain errors. |
| `ModeScreen` | Capture a mode screen, such as copy mode. |
| `Pending` | Capture an incomplete pending escape sequence. |
| `Hyperlinks` | Include supported hyperlink capture metadata. |
| `LineNumbers` | Include supported line-number metadata. |
| `LineFlags` | Include supported line-flag metadata. |

`-PreserveTrailingSpaces` and `-TrimTrailingSpaces` together terminate with
`Tmux.InvalidCapture` before dispatch. Version-dependent switches retain the
core's capability policy; availability depends on the tmux version and the
core connection's configuration.

## Refresh captured metadata

Retain the replacement returned by an explicit refresh:

<!-- example: capture.refresh -->
```powershell
$currentPane = $pane | Update-TmuxPane
```

The original `$pane` keeps its previously captured values. Refresh observes
tmux and returns another native `LibTmux.Pane`; it does not mutate terminal
state or acquire ownership of the daemon. It uses the core's refresh and
identity rules. Repeated linked-window placement refresh remains subject to
the core's contextual-target limitations.

## Run literal tmux arguments

Pass each argument as a separate array element. The adapter does not join
arguments into a shell command or expand their contents.

<!-- example: capture.raw-list -->
```powershell
$server | Invoke-TmuxCommand -Arguments @('list-sessions', '-F', '#{session_name}')
```

Empty non-command arguments are preserved. The first argument must name a
command or alias. An empty, whitespace or leading-option argument terminates
with `Tmux.InvalidCommand` before confirmation or dispatch. Select the socket
on the server handle; global options such as `-S`, `-L` and `-f` cannot replace
the command name. Arbitrary `Id` or `Server` object properties do not bind as
an endpoint.

Raw commands can mutate tmux or execute shell work. They always support
`-WhatIf` and `-Confirm`, including for commands the caller knows are reads.
Confirmation precedes discovery and dispatch. Preview shows the endpoint and
command name; argument contents are not included in the confirmation text.

<!-- example: capture.raw-preview -->
```powershell
$server | Invoke-TmuxCommand -Arguments @('kill-session', '-t', '$3') -WhatIf
```

Successful execution emits a native `LibTmux.TmuxCommandResult` with exit code,
logical arguments, stdout/stderr bytes and projected lines. A nonzero exit
emits no success result and writes `Tmux.CommandFailed`. Its original
`TmuxCommandException.Result` retains those diagnostics, and its `Dispatch`
is `Dispatched`. Transport failures preserve their original exception and
dispatch uncertainty. No mutation is automatically retried.

Capture and refresh failures use `Tmux.PaneCaptureFailed` and
`Tmux.PaneRefreshFailed`. Each error retains the failed owner, allowing later
pipeline owners to continue unless `-ErrorAction Stop` is selected.
Cancellation uses the same core token and pipeline lifecycle as the read
cmdlets; it does not imply rollback or termination of shell work.

The [capture integration test](../tests/Capture.Tests.ps1) exercises these
contracts against an owned daemon with explicit output readiness, literal
argument round trips, error results, refresh replacement and zero-dispatch
`-WhatIf`. It owns its sockets, child processes and temporary files.
