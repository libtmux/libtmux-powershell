# Compatibility

This source checkout targets PowerShell 7.4 and .NET 8. The Linux workflow
tests the specific PowerShell and tmux versions below; other combinations
remain unverified. [LibTmux](https://www.powershellgallery.com/packages/LibTmux)
and [LibTmux.Workspace](https://www.powershellgallery.com/packages/LibTmux.Workspace)
are published as prereleases on PowerShell Gallery. Both pin
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
Development builds rank below the release they name: `next-3.3a` and
`3.3a-rc` do not qualify, and a report without a dated release, such as
`master`, is refused.

Every cmdlet that talks to tmux goes through the linked
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

Optional features can need a newer release than this floor. Their
requirements belong to the cmdlet that needs them and are listed with the
feature rather than raised for the whole module.

## Optional features

A feature that needs a newer release is refused for that cmdlet alone, with
`LibTmux.TmuxVersionTooLowException`; the error names the release it needs
and nothing is sent first. Each requirement is per feature, so the floor for
reads, writes, raw commands and workspaces stays tmux 3.3a.

| Feature | Needs | Below that release |
| --- | --- | --- |
| `Connect-TmuxControl`, `Watch-TmuxEvent` with a server | 3.7 | Refused before a control client attaches. Short-lived control clients can crash tmux servers before 3.7 while they identify themselves (measured on 3.2a and 3.6b; 3.7c and 3.8 survived every trial), and the linked .NET package would attach first and fall back afterwards. |
| `Invoke-TmuxPaneCommand` | 3.4 | Refused before it stages a temporary named buffer. Before 3.4, deleting a missing buffer by name removes an unrelated one. |
| Literal `delete-buffer -b` and `set-buffer -b ... -n` items | 3.4 | Refused by `Invoke-TmuxCommand` and `Invoke-TmuxChain`. |
| Literal `break-pane` without `-n` | not exactly 3.7 | Refused on tmux 3.7, which crashes on it. Name the window. |
| Session and window names containing `:` or `.` | not exactly 3.7 | Refused on tmux 3.7, which rejects them, by `New-TmuxSession`, `New-TmuxWindow`, `Invoke-TmuxWorkspace` and literal command items. |
| Literal `split-window -p` | not exactly 3.4 | Refused on tmux 3.4, which breaks it. Use `-l` with a percentage such as `30%`. |

`Wait-TmuxPaneText` needs no refusal: it attaches no control client below
3.7 and polls the pane instead.

The guards cover typed operations, workspace plans and literal command items
sent through `Invoke-TmuxCommand` and `Invoke-TmuxChain`. Commands typed into
a pane, text inside an `if-shell` string and aliases in your tmux
configuration are outside them. A connection you open yourself and pass to
`Watch-TmuxEvent -Connection` was acquired before the module could decide.

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
$ Install-Module -Name LibTmux -AllowPrerelease
```

Or install the workspace module with its matching core dependency:

```console
$ Install-Module -Name LibTmux.Workspace -AllowPrerelease
```

Choose one installer. The prerelease flag includes the alpha releases;
without it, the installers look for stable releases. Both Gallery pages also
provide Azure Automation and manual download options. A manual download does
not include dependencies; use a package manager to resolve them. Azure
Automation runs need a host with PowerShell and tmux as described above.
