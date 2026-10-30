# Compatibility

This source checkout targets PowerShell 7.4 and .NET 8. The Linux workflow
tests the specific PowerShell and tmux versions below; other combinations
remain unverified. [LibTmux](https://www.powershellgallery.com/packages/LibTmux)
and [LibTmux.Workspace](https://www.powershellgallery.com/packages/LibTmux.Workspace)
are published on PowerShell Gallery. Both pin
[libtmux for .NET](https://github.com/libtmux/libtmux-dotnet).
See the [install guide](../README.md#quick-start) for package-manager commands
and source builds. Publication does not expand the tested platforms below.

| Environment | Contract |
| --- | --- |
| Linux x64 | The [Linux workflow](../.github/workflows/ci.yml) exercises PowerShell 7.4.20 and 7.6.6 with tmux 3.3a, 3.4, 3.5, 3.6, 3.7a, 3.7b, 3.7c, 3.8 and the current tmux master (`next-3.9`). Check the run for the commit you use; a green older commit does not verify newer code. |
| WSL2 | Run PowerShell and tmux inside the same Linux environment. The Windows host's PowerShell process is outside this contract. |
| macOS | Intel and Apple Silicon have an advisory [eight-cell trial](../.github/workflows/macos-trial.yml). Suite failures appear in its job summaries and artifacts without failing the trial check; they do not establish support. |
| Native Windows and psmux | Outside this port's scope. |

## Minimum tmux version

The minimum for ordinary operations is tmux 3.3a. Versions compare as whole
releases, so 3.3 is below the floor and 3.3a is the first supported release.
Development builds and release candidates rank below the release they name:
`next-3.3a` and a candidate of 3.3a do not qualify, and a report without a
dated release, such as `master`, is refused.

tmux release candidates are not supported: a feature can require one only
until its release ships. See [Release candidates](https://libtmux.org/en/tmux/guides/tmux-support/#release-candidates).

## Optional features

A feature that a release cannot run safely is refused for that cmdlet alone;
the error says why, and nothing is sent first. Each requirement is per
feature, so the floor for reads, writes, raw commands and workspaces stays
tmux 3.3a.

[`capabilities.json`](../capabilities.json) is the machine-readable list of
these features: each entry names the capability, the release it needs, the
error and the cmdlets it gates. The `id` in the last column names the entry
and its [evidence](#evidence).

| Feature | Needs | Below that release | Id |
| --- | --- | --- | --- |
| `Connect-TmuxControl`, `Watch-TmuxEvent` with a server | 3.7 | Refused before a control client attaches. | [`control-mode`](#evidence) |
| `Invoke-TmuxPaneCommand` | 3.4 | Refused before it stages a named buffer. | [`buffer-delete-named`](#evidence) |
| Literal `delete-buffer -b` | 3.4 | Refused by the raw-command cmdlets. | [`buffer-delete-named`](#evidence) |
| Literal `set-buffer -b ... -n` | 3.4 | Refused by the raw-command cmdlets. | [`buffer-rename`](#evidence) |
| Literal `break-pane` without `-n` | not exactly 3.7 | Refused on 3.7. Name the window. | [`break-pane-misnames-windows`](#evidence) |
| Session and window names with `:` or `.` | not exactly 3.7 | Refused on 3.7. | [`name-separators-rejected`](#evidence) |
| Literal `split-window -p` | not exactly 3.4 | Refused on 3.4. Use `-l` with a percentage such as `30%`. | [`split-window-percent-size`](#evidence) |
| Literal `refresh-client -l` | 3.6a | Refused by the raw-command cmdlets. | [`clipboard-query`](#evidence) |
| Literal `select-layout` with a layout string | 3.4 for a layout without a checksum | Refused by the raw-command cmdlets. Use a preset name or a layout read from tmux. | [`layout-without-checksum`](#evidence) |
| `Set-TmuxLayout` with `main-horizontal-mirrored` or `main-vertical-mirrored` | 3.5 | Refused. Use another preset. | [`layout-mirrored-main`](#evidence) |
| `Set-TmuxLayout` or a workspace window (`Get-TmuxWorkspacePlan`) with a JSON layout | 3.8 | Refused. Use the checksummed layout from [`$window.Layout`](https://libtmux.org/en/csharp/latest/reference/libtmux-window-layout/). The raw-command cmdlets and control connections are not gated; tmux reports the error. | [`layout-json`](#evidence) |

The raw-command cmdlets are `Invoke-TmuxCommand`, `Invoke-TmuxChain` and
`Invoke-TmuxControlCommand`. `Wait-TmuxPaneText` needs no refusal: it attaches
no control client below 3.7 and polls the pane instead.

Every refusal raises one type, `LibTmux.TmuxUnsupportedOnReleaseException`,
whichever cmdlet or literal command meets it. Where a plain release floor
decides, the error is its subclass `LibTmux.TmuxVersionTooLowException`, so
one `catch` of the base type covers both and a `catch` of the subclass keeps
working for those rows. The exception carries `ActualVersion`, `SafeReleases`,
`CapabilityId` and `Command`.

A workspace layout that the daemon's release lacks fails planning with
`LibTmux.Workspace.WorkspaceFormatException`, which names the layout path and
carries the refusal as its `InnerException`. The error still reports the
`NotImplemented` category.

These inputs are caller errors on every release and are not release refusals:

- A session name with `:` or `.` raises `System.ArgumentException` from
  `New-TmuxSession`.
- A layout string that is malformed or unknown raises
  `LibTmux.TmuxWindowException` from `Set-TmuxLayout`.

`capabilities.json` names the error of each entry and each workaround, and its
`apis` list only the cmdlets that raise that error.

### Evidence

Each requirement rests on a published source. The libtmux for .NET pages are
pinned to the commit of the release these modules build on.

- `control-mode`: before 3.7, a notification that fires while a control
  client identifies itself crashes the whole server, as the
  [libtmux for .NET one-shot guide](https://github.com/libtmux/libtmux-dotnet/blob/b1e8156/docs/modes/one-shot.md?plain=1#L46-L50) records with the tmux commit
  that changed it. The same package's [version matrix](https://github.com/libtmux/libtmux-dotnet/blob/b1e8156/docs/modes/matrix.md?plain=1#L178)
  lists the requirement.
- `buffer-delete-named` and `buffer-rename`: before 3.4, a buffer name that
  does not exist acts on the most recent buffer instead of failing. See the
  [version matrix](https://github.com/libtmux/libtmux-dotnet/blob/b1e8156/docs/modes/matrix.md?plain=1#L181).
- `break-pane-misnames-windows`: `break-pane` without `-n` ends a 3.7 server.
  tmux 3.7a lists
  ["Fix crash in break-pane when no name is provided"](https://github.com/tmux/tmux/blob/0e418b6/CHANGES#L1-L8). See also the
  [version matrix](https://github.com/libtmux/libtmux-dotnet/blob/b1e8156/docs/modes/matrix.md?plain=1#L183).
- `name-separators-rejected`: 3.7 rejects `:` and `.` in names. tmux 3.7a lists
  ["Only forbid #( in names, allow #[, empty names, : and ."](https://github.com/tmux/tmux/blob/0e418b6/CHANGES#L1-L8). See also
  the [version matrix](https://github.com/libtmux/libtmux-dotnet/blob/b1e8156/docs/modes/matrix.md?plain=1#L184).
- `split-window-percent-size`: `split-window -p` is broken on 3.4. tmux 3.5
  lists ["Fix split-window -p"](https://github.com/tmux/tmux/blob/ac44566/CHANGES#L88). See also the
  [version matrix](https://github.com/libtmux/libtmux-dotnet/blob/b1e8156/docs/modes/matrix.md?plain=1#L185).
- `clipboard-query`: before 3.6a, `refresh-client -l` can end the server when
  the attached client leaves before its terminal answers, and on 3.3a it ends
  the server with a client attached. tmux 3.6a lists
  ["Newer libevents do not allow event_del on a zero'd event"](https://github.com/tmux/tmux/blob/cc117b5/CHANGES#L21),
  the [commit](https://github.com/tmux/tmux/commit/0af04295f) that sets up the
  clipboard query's timer when a client's terminal opens. See also the
  [version matrix](https://github.com/libtmux/libtmux-dotnet/blob/b1e8156/docs/modes/matrix.md?plain=1#L187).
- `layout-without-checksum`: a layout string that is neither checksummed nor
  a preset name ends tmux 3.3a. The [version matrix](https://github.com/libtmux/libtmux-dotnet/blob/b1e8156/docs/modes/matrix.md?plain=1#L186) lists the
  requirement.
- `layout-mirrored-main`: tmux 3.5 lists
  ["Add mirrored versions of the main-horizontal and main-vertical layouts"](https://github.com/tmux/tmux/blob/ac44566/CHANGES#L27), so
  an earlier release rejects the preset. See also the
  [refusal types](https://github.com/libtmux/libtmux-dotnet/blob/b1e8156/docs/modes/matrix.md?plain=1#L196-L199).
- `layout-json`: tmux 3.8 lists
  ["Layout strings now use a JSON subset format"](https://github.com/tmux/tmux/blob/7f2a35a/CHANGES#L38), so an
  earlier release rejects the JSON form.

### What the checks do not read

The checks read the command a cmdlet is given. They do not read a refused
command carried inside another command's text: an `if-shell` or `run-shell -C`
string, a `bind-key`, `set-hook` or `confirm-before` command, a menu, prompt
or choose template, a brace block, or an alias in your tmux configuration.
Commands typed into a pane are outside them too. Nested, a refused command
reaches tmux unchanged, and it fails as follows.

| What happens | Command | Releases |
| --- | --- | --- |
| The server exits | `break-pane` without `-n`, direct or nested | Exactly 3.7; fixed in 3.7a |
| The server exits | `select-layout` with an invalid layout string that has no checksum | 3.3a; 3.4 answers with an error and stays up |
| The server exits | `refresh-client -l`, when an attached client leaves or does not answer the clipboard query | Below 3.6a |
| A different buffer is changed, with no error | `delete-buffer -b NAME`, `set-buffer -b NAME -n`, when NAME does not exist | Below 3.4: the most recent buffer is used instead |
| tmux answers with an error and nothing changes | `split-window -p` | Exactly 3.4 |
| tmux answers with an error and nothing changes | `:` or `.` in a session or window name | Exactly 3.7 |

On exactly tmux 3.7, name every `break-pane`, including the one the `prefix !`
key runs, or upgrade to 3.7a or later. Do not nest any other command that
this page lists as refused.

## How the check works

Every cmdlet that talks to tmux goes through the
[libtmux for .NET](https://github.com/libtmux/libtmux-dotnet) package, which
reads the version of the connected daemon first and refuses an older or
unreadable one before it sends anything. The client executable does not
decide this: an older daemon is refused even when the selected executable
reports a newer version. Operations return a `LibTmux.TmuxVersionTooLowException`
error rather than an empty result. When no daemon answers, the executable's own
version is checked before it can start one; a read, which starts nothing,
reports the missing daemon instead. The check adds no tmux hook activity: it
asks for a `run-shell -C` expansion that tmux rejects while parsing, so no
`after-*` hook and no `command-error` hook fires for it.

Every command list the package sends starts with a guard on the checked
version. If a different daemon replaced the first one in between, the list
fails before any command runs. A replacement that is supported is checked
again and the command is sent once more; one below the floor is refused; a
second mismatch reports that the daemon changed and that the command did not
run. A client that finds the checked daemon gone starts none.

The Linux workflow keeps tmux 3.2a and unpatched 3.3 as rejection lanes. They
run only the version check suite, which checks that reads, creation, raw commands
and chains are refused and that nothing changed.

A daemon older than 3.2 cannot report its version through that check: a 3.1c
daemon answers with the `run-shell` usage line, and a 3.0a daemon makes the
client print `server version is too old for client`. A client older than 3.2
rejects the `-N` flag the check passes, so its own version decides. All three
are refused with `TmuxVersionTooLowException`, which says what to do: upgrade
tmux and restart the tmux server, or use an older release. The message names
the last libtmux for .NET release that supports older tmux, 0.0.0-alpha.21;
for these modules it is 0.1.0-alpha2.

The Linux workflow also runs real 3.0a and 3.1c daemons behind a 3.3a client
and requires the refusal to come back promptly.

A refusal is a non-terminating error, like every other operation failure in
the module, so it follows `-ErrorAction`. Use `-ErrorAction Stop` where a
refused daemon must not fall through as no output, as in
`Get-TmuxSession -ErrorAction SilentlyContinue`, which hides it.

`Connect-TmuxControl` attaches only after the same check, so
`Invoke-TmuxControlCommand` and `Watch-TmuxEvent` need no check of their own on
the connection it returns.

`Invoke-TmuxCommand kill-server` against an endpoint where no daemon answers
returns an empty successful result without dispatching anything.

The separate [MCP tool](mcp.md) is built on the same package and refuses the
same daemons.

One registry in the module holds these requirements, and it writes
[`capabilities.json`](../capabilities.json) for the capabilities page of the
documentation site. The module reads the daemon's version and infers what that
release can do; tmux does not report its capabilities, so a patched build is
judged as the release it names.

The module checks the typed operations and workspace plans itself. Literal
command items sent through `Invoke-TmuxCommand`, `Invoke-TmuxChain` and
`Invoke-TmuxControlCommand` are checked by the libtmux for .NET package, which
reads a command word the way tmux does, by alias, name or unique prefix, and
reads a `;` list one command at a time.
[What the checks do not read](#what-the-checks-do-not-read) lists the nested
commands they skip.

The version a guard reads is the daemon's, taken just before the command is
sent. A daemon replaced in that moment is not caught by the guard, though the
package's own check still refuses one below the floor.

Sections of the suites that need a control client or a pane command report
SKIP below their releases rather than pass, and the features suite asserts
the refusals and that nothing changed. The guards for exactly 3.7, a release
the workflow does not run, are tested by reporting that version to the
version probe.

Choose the tmux executable and socket explicitly with
[New-TmuxServer](read.md). A handle alone starts no daemon. The module does
not change `TMUX` or `TMUX_PANE` in the calling process, and it does not
connect to an implicit global server during import or formatting.

Some tmux flags and format expressions vary by version. The typed API
checks capabilities where it can; [query plans](query.md) show source
pushdown and residual work before execution. A failed or unknown capability
check is not an empty result. [Capture options](capture.md) identify flags
whose availability depends on tmux. Use an explicit
[raw command](capture.md#run-literal-tmux-arguments) for less common tmux
operations and inspect its result or error record.

The workspace module is a separate PowerShell package over the shared .NET
workspace engine. The [MCP server](mcp.md) is a separate .NET tool that does
not require PowerShell. Its client protocol, toolsets, and task support must
be discovered from the installed executable rather than inferred from the
PowerShell module version.

See [troubleshooting](troubleshooting.md) for endpoint, package, input and
stream failures.

## Install with PowerShellGet

The README installs with PSResourceGet, which PowerShell 7.4 includes.
PowerShellGet installs the same packages. Install the core module:

```console
$ Install-Module -Name LibTmux
```

Or install the workspace module with its matching core dependency:

```console
$ Install-Module -Name LibTmux.Workspace
```

Choose one installer. Both Gallery pages also provide Azure Automation and
manual download options. A manual download does not include dependencies; use
a package manager to resolve them. Azure Automation runs need a host with
PowerShell and tmux as described above.
