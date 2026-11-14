# Capture, refresh and raw commands

- `Get-TmuxPaneContent` reads rendered text from a `LibTmux.Pane`.
- `Update-TmuxPane` reads current pane metadata into a replacement handle.
- `Invoke-TmuxCommand` sends literal tmux arguments to a `LibTmux.Server`, for
  operations that have no dedicated cmdlet.

The pane cmdlets accept a pane directly or from the pipeline and borrow its
daemon. The examples assume `$pane` and `$server` are the pane and server
selected as in [Read tmux objects](read.md); none picks a global active server.

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
its fifth line. Zero is the top visible line and negative values address
scrollback. Omitted bounds use the visible screen.

<!-- example: capture.range -->
```powershell
$pane | Get-TmuxPaneContent -StartLine -10 -EndLine 4
```

- `-History` selects the oldest retained history. It combines with `-EndLine`
  but not `-StartLine`.
- `-Raw` emits one string per pane, joining lines with LF and adding no
  trailing newline. Internal empty lines stay. An empty capture emits nothing,
  or one empty string with `-Raw`.

The result is rendered terminal text, not the process's original output or a
byte-exact stream. Sending input or receiving a pane-output event does not mean
a command finished. Wait for a completion signal from the application, such as a
cooperative wait channel, or use
[Invoke-TmuxPaneCommand](input.md#run-a-command-to-completion), before relying
on its output.

| Switch | Effect |
| --- | --- |
| [`JoinWrappedLines`][-joinwrappedlines] | Join lines that wrapped on screen; tmux applies this in place of trailing-space handling. |
| [`EscapeSequences`][-escapesequences] | Include terminal escape sequences representing captured attributes. |
| [`EscapeNonPrintable`][-escapenonprintable] | Represent nonprintable bytes with octal escapes. |
| [`PreserveTrailingSpaces`][-preservetrailingspaces] | Retain trailing spaces. |
| [`TrimTrailingSpaces`][-trimtrailingspaces] | Request tmux's trailing-space trimming behavior. |
| [`AlternateScreen`][-alternatescreen] | Capture the alternate screen. |
| [`Quiet`][-quiet] | Return empty content when an alternate screen is absent; other failures remain errors. |
| [`ModeScreen`][-modescreen] | Capture a mode screen, such as copy mode. |
| [`Pending`][-pending] | Capture an incomplete pending escape sequence. |
| [`Hyperlinks`][-hyperlinks] | Include supported hyperlink capture metadata. |
| [`LineNumbers`][-linenumbers] | Include supported line-number metadata. |
| [`LineFlags`][-lineflags] | Include supported line-flag metadata. |

`-PreserveTrailingSpaces` and `-TrimTrailingSpaces` together fail with
[`Tmux.InvalidCapture`][gettmuxpanecontentcommand] before dispatch. Some
switches depend on the tmux version and the core connection's configuration.

## Refresh captured metadata

Retain the replacement returned by an explicit refresh:

<!-- example: capture.refresh -->
```powershell
$currentPane = $pane | Update-TmuxPane
```

The original `$pane` keeps its captured values. Refresh reads tmux and returns
another `LibTmux.Pane`; it changes no terminal state and takes no ownership of
the daemon. Refreshing a pane in a repeatedly linked window is subject to the
core's contextual-target limits.

## Run literal tmux arguments

Pass each argument as a separate array element. Nothing joins them into a shell
command or expands their contents.

<!-- example: capture.raw-list -->
```powershell
$server | Invoke-TmuxCommand -Arguments @(
    'list-sessions', '-F', '#{session_name}'
)
```

The same literal arguments reach features without a cmdlet. This creates a
named paste buffer, reads it and removes only that buffer. Deleting a buffer by
name needs tmux 3.4 or newer, because earlier releases act on another buffer
when the name is missing; `Invoke-TmuxCommand` refuses it there:

<!-- example: capture.buffer -->
```powershell
& {
    $name = 'libtmux-' + [guid]::NewGuid().ToString('N')
    $quiet = @{ Confirm = $false; ErrorAction = 'Stop' }
    $created = $false
    try {
        $set = @('set-buffer', '-b', $name, 'hello from PowerShell')
        $null = $server | Invoke-TmuxCommand -Arguments $set @quiet
        $created = $true
        $show = @('show-buffer', '-b', $name)
        $shown = $server | Invoke-TmuxCommand -Arguments $show @quiet
        $shown.StandardOutputLines
    } finally {
        if ($created) {
            $delete = @('delete-buffer', '-b', $name)
            $server | Invoke-TmuxCommand -Arguments $delete @quiet | Out-Null
        }
    }
}
```

This returns `hello from PowerShell`. `StandardOutput` keeps the bytes when
lines do not fit.

For copy mode, send raw `copy-mode` and `send-keys -X` commands with an
explicit pane ID, and read the screen with
`Get-TmuxPaneContent -ModeScreen`. Copy mode changes the pane's mode, so leave
it with `send-keys -X cancel`.

- **Arguments:** empty non-command arguments are kept. The first must name a
  command or alias; an empty, whitespace or leading-option first argument fails
  with [`Tmux.InvalidCommand`][invoketmuxcommandcommand] before confirmation or
  dispatch.
- **Socket:** select it on the server handle. Global options such as `-S`, `-L`
  and `-f` cannot replace the command name.
- **Pipeline:** input must be a `LibTmux.Server`; an object with similar
  property names does not bind.
- **Confirmation:** raw commands can mutate tmux or run shell work, so they
  always support `-WhatIf` and `-Confirm`, even for reads. Confirmation comes
  before discovery and dispatch, and shows the endpoint and command name but not
  the arguments.

<!-- example: capture.raw-preview -->
```powershell
$server | Invoke-TmuxCommand -Arguments @('kill-session', '-t', '$3') -WhatIf
```

## Results and errors

- **Success:** a `LibTmux.TmuxCommandResult` with the exit code, logical
  arguments, stdout and stderr bytes, and projected lines.
- **Nonzero exit:** no success result; it writes
  [`Tmux.CommandFailed`][invoketmuxcommandcommand]. The
  `TmuxCommandException.Result` keeps the diagnostics, and its `Dispatch` is
  `Dispatched`.
- **Transport failure:** keeps the original exception and whether dispatch is
  uncertain. No mutation is retried.
- **Capture and refresh:** failures use
  [`Tmux.PaneCaptureFailed`][gettmuxpanecontentcommand] and
  [`Tmux.PaneRefreshFailed`][updatetmuxpanecommand]. The error keeps the failed
  owner, and later pipeline owners continue unless you pass
  `-ErrorAction Stop`.
- **Cancellation:** uses the read cmdlets' token and lifecycle. It does not roll
  back or stop shell work.

[-joinwrappedlines]: reference/LibTmux/Get-TmuxPaneContent.md#-joinwrappedlines
[-escapesequences]: reference/LibTmux/Get-TmuxPaneContent.md#-escapesequences
[-alternatescreen]: reference/LibTmux/Get-TmuxPaneContent.md#-alternatescreen
[-quiet]: reference/LibTmux/Get-TmuxPaneContent.md#-quiet
[gettmuxpanecontentcommand]: ../src/LibTmux.PowerShell/GetTmuxPaneContentCommand.cs
[invoketmuxcommandcommand]: ../src/LibTmux.PowerShell/InvokeTmuxCommandCommand.cs
[updatetmuxpanecommand]: ../src/LibTmux.PowerShell/UpdateTmuxPaneCommand.cs
[-escapenonprintable]: reference/LibTmux/Get-TmuxPaneContent.md#-escapenonprintable
[-preservetrailingspaces]: reference/LibTmux/Get-TmuxPaneContent.md#-preservetrailingspaces
[-trimtrailingspaces]: reference/LibTmux/Get-TmuxPaneContent.md#-trimtrailingspaces
[-modescreen]: reference/LibTmux/Get-TmuxPaneContent.md#-modescreen
[-pending]: reference/LibTmux/Get-TmuxPaneContent.md#-pending
[-hyperlinks]: reference/LibTmux/Get-TmuxPaneContent.md#-hyperlinks
[-linenumbers]: reference/LibTmux/Get-TmuxPaneContent.md#-linenumbers
[-lineflags]: reference/LibTmux/Get-TmuxPaneContent.md#-lineflags
