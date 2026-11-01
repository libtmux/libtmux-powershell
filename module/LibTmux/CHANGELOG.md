# Changelog

Notable changes to `LibTmux`.

The modules are released together at one version, so every release has a section
here. Changes that span both modules, such as documentation, development and
packaging, are in the [main
changelog](https://github.com/libtmux/libtmux-powershell/blob/master/CHANGELOG.md).

## 0.1.1 - Unreleased

No entries for `LibTmux`.

## 0.1.0 - 2026-10-25

### Breaking changes

#### Catch one type for release refusals

Every refusal a tmux release causes now raises
`LibTmux.TmuxUnsupportedOnReleaseException`, from libtmux for .NET
0.0.0-alpha.24, whichever cmdlet or literal command meets it. It carries
`ActualVersion`, `SafeReleases`, `CapabilityId` and `Command`.
`TmuxVersionTooLowException` derives from it and is still raised where a
release floor decides.

Before, a window name with `:` or `.` on exactly tmux 3.7 raised
`System.ArgumentException`, a literal `select-layout` that tmux below 3.4
crashes on raised `System.ArgumentException`, and `Set-TmuxLayout` with a
mirrored layout below tmux 3.5 or a JSON layout below 3.8-rc2 raised
`LibTmux.TmuxWindowException`. The name and literal-layout refusals came from `New-TmuxSession`,
`New-TmuxWindow`, `Invoke-TmuxWorkspace` and the raw-command cmdlets. All now
raise `TmuxUnsupportedOnReleaseException`, which has no `WindowId`; the
window is in the message. The `ErrorRecord` category for these cases changes
too: `InvalidArgument` for the old `ArgumentException` and `InvalidOperation`
for the old `TmuxWindowException` are now `NotImplemented`, as for a floor
refusal. A workspace layout the release lacks fails planning as
`LibTmux.Workspace.WorkspaceFormatException` with the refusal as its
`InnerException`. Catch the base type where you caught
`ArgumentException` or `TmuxWindowException` for these cases. A catch of
`TmuxVersionTooLowException` needs no change.

A session name with `:` or `.` still raises `ArgumentException` from
`New-TmuxSession`, and a malformed or unknown layout still raises
`TmuxWindowException` from `Set-TmuxLayout`, because both are invalid on every
release. `capabilities.json` now names an error for each workaround, lists
`layout-mirrored-main` and `layout-json`, and limits the `apis` of
`layout-without-checksum` to the cmdlets that raise its error. (#41)

## 0.1.0-alpha3 - 2026-10-24

### Breaking changes

#### Poll for pane text below tmux 3.7

`Wait-TmuxPaneText` attaches no control client on tmux before 3.7. It polls
without `-AllowPollingFallback` and reports `PollingFallback` as true. On 3.7
and newer, control observation is still required unless the switch is given.
(#21)

#### Share one control client on tmux 3.7 and newer

Commands sent from one server handle now share a control client. A blocking
command nested in a list, such as `if-shell -F 1 'wait-for release'`, holds the
commands behind it, and a `wait-for` at the top level still runs on its own.
Set `LIBTMUX_CONTROL_TRANSPORT=0` before creating the server handle to send
each command from its own process. (#21)

#### Refuse optional features on older tmux

A feature that needs a newer release than the 3.3a floor is refused for that
cmdlet alone, with `TmuxVersionTooLowException` and before anything is sent.
`Connect-TmuxControl` and `Watch-TmuxEvent` with a server need tmux 3.7, because
a short-lived control client crashed tmux 3.2a and 3.6b servers while it
identified itself. `Invoke-TmuxPaneCommand` and literal `delete-buffer -b` and
`set-buffer -n` items need 3.4.

The literal items of `Invoke-TmuxCommand`, `Invoke-TmuxChain` and
`Invoke-TmuxControlCommand` are also checked, by the libtmux for .NET package,
which reads a command word the way tmux does, by alias, name or unique prefix.
On exactly tmux 3.7, `break-pane` without `-n` crashes the server and a `:` or
`.` in a session or window name is rejected, so both are refused, as is such a
name in `New-TmuxSession`, `New-TmuxWindow` and `Invoke-TmuxWorkspace`. Such a
name is refused with `ArgumentException`, typed or literal, not
`TmuxVersionTooLowException`. On exactly 3.4, `split-window -p` is refused;
`-l` with a percentage works. `refresh-client -l`, the clipboard query, needs
3.6a, because it ends 3.3a at once with a client attached and 3.4 through 3.6
when the client leaves before its terminal answers. A layout string without a
checksum, which crashes tmux before 3.4, is refused by `Set-TmuxLayout`, and a
literal `select-layout` item holding one is refused with `ArgumentException`.
Everything else stays available from 3.3a. (#22)

### Bug fixes

- Match a pane text line that wraps across rows in `Wait-TmuxPaneText`, while it
  polls and on a control client, and end the wait as `PaneExited` with the
  output read so far instead of reporting a raw error when the server is killed
  under it, even when a stopped second control client keeps the server up. The
  result always carries its `Tail`. (#22)

## 0.1.0-alpha2 - 2026-10-10

No entries for `LibTmux`.

## 0.1.0-alpha1 - 2026-10-10

### What's new

#### New module: `LibTmux`

Create, inspect, arrange and remove tmux sessions, windows and panes through
native PowerShell pipelines. Capture their object graph explicitly, then
navigate linked windows and filter native .NET objects locally. (#1)

- Select with validated criteria, inspect source-query plans and explicitly
  acquire fresh results. Ordinary `Where-Object` pipelines remain available.
  (#1)

- Run pane commands to an exit result, send literal input, wait for readiness
  and consume bounded event streams. Reuse control connections or ordered
  command chains with cancellation and partial-effect reporting. (#1)
