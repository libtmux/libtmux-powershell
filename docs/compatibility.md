# Compatibility

This source checkout targets PowerShell 7.4 and .NET 8. The Linux workflow
tests the specific PowerShell and tmux versions below; other combinations
remain unverified. [LibTmux](https://www.powershellgallery.com/packages/LibTmux)
and [LibTmux.Workspace](https://www.powershellgallery.com/packages/LibTmux.Workspace)
are published as prereleases on PowerShell Gallery. Both pin
[libtmux for .NET](https://github.com/libtmux/libtmux-dotnet).
See the [install guide](../README.md#install) for package-manager commands
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

Every cmdlet that talks to tmux first reads the version of the connected
daemon and refuses an older or unreadable one before it changes anything. The
client executable does not decide this: an older daemon is refused even when
the selected executable reports a newer version. Reads return a
`LibTmux.TmuxVersionTooLowException` error rather than an empty result. When
no daemon answers, the executable's own version is checked before it can
start one. The read adds no tmux hook activity: no `after-*` hook and no
`command-error` hook fires for it.

`Invoke-TmuxCommand` and `Invoke-TmuxChain` also tie the batch to the version
they checked. If a different daemon replaced the first one in between, the
batch fails before any command runs. The linked library handles typed
operations one command at a time, so a daemon replaced mid-operation is not
caught by those.

The Linux workflow keeps tmux 3.2a and unpatched 3.3 as rejection lanes. They
run only the version check suite, which checks that reads, creation, raw commands
and chains are refused and that nothing changed. The shared .NET package
still lists 3.2a as its own minimum, and it reads only a `tmux <version>`
banner, so a 3.3a executable renamed to anything else cannot start a daemon
through the typed commands.

A refusal is a non-terminating error, like every other operation failure in
the module, so it follows `-ErrorAction`. Use `-ErrorAction Stop` where a
refused daemon must not fall through as no output, as in
`Get-TmuxSession -ErrorAction SilentlyContinue`, which hides it.

`Invoke-TmuxControlCommand` on a connection that `Connect-TmuxControl` opened
uses the version checked before the attach. For a connection opened another
way, pass `-Server`: the usual hook-free probe runs against that endpoint
and the connection is remembered. The connection could belong to a different
daemon only if the endpoint was replaced between its attach and the call.

`Invoke-TmuxCommand kill-server` against an endpoint where no daemon answers
returns an empty successful result without dispatching anything.

The separate [MCP tool](mcp.md) is not part of this change. It keeps the
linked .NET package's own floor until that package checks the daemon's version itself;
typed calls here can then rely on the package and the cmdlet-level version check
can shrink.

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
| `Connect-TmuxControl`, `Watch-TmuxEvent` with a server | 3.7 | Refused before a control client attaches. Control clients can crash tmux servers before 3.7 while they identify themselves (measured on 3.2a and 3.6b; 3.7c and 3.8 survived every trial), and the linked .NET package would attach first and fall back afterwards. |
| `Wait-TmuxPaneText` | 3.3a (control from 3.7) | Below 3.7 it polls `capture-pane` every 100 ms and attaches nothing. It sees rendered rows, so text that scrolls past between polls can be missed, and its result carries the outcome, pattern and elapsed time only. |
| `Invoke-TmuxPaneCommand` | 3.4 | Refused before it stages a temporary named buffer. Before 3.4, deleting a missing buffer by name removes an unrelated one. |
| Literal `delete-buffer -b` and `set-buffer -b ... -n` items | 3.4 | Refused by `Invoke-TmuxCommand` and `Invoke-TmuxChain`. |
| Literal `break-pane` without `-n` | not exactly 3.7 | Refused on tmux 3.7, which crashes on it. Name the window. |
| Session and window names containing `:` or `.` | not exactly 3.7 | Refused on tmux 3.7, which rejects them, by `New-TmuxSession`, `New-TmuxWindow`, `Invoke-TmuxWorkspace` and literal command items. |
| Literal `split-window -p` | not exactly 3.4 | Refused on tmux 3.4, which breaks it. Use `-l` with a percentage such as `30%`. |

The guards cover typed operations, workspace plans and literal command items
sent through `Invoke-TmuxCommand`, `Invoke-TmuxChain` and
`Invoke-TmuxControlCommand`. Commands typed into a pane, text inside an
`if-shell` string and aliases in your tmux configuration are outside them.
A connection you open yourself and pass to `Invoke-TmuxControlCommand` or
`Watch-TmuxEvent -Connection` was acquired before the module could decide,
but the daemon behind it is still checked before a command is sent.

The Linux workflow runs the full suites on tmux 3.3a and 3.7c. Sections
that need a control client or a pane command report SKIP below their
releases rather than pass, and the features suite asserts the refusals and
that nothing changed. Releases between those two are not exercised in
routine CI, and the guards for 3.4 and exactly 3.7 are tested by reporting
that version to the version probe.

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
