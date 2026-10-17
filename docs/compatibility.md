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
| Linux x64 | The [Linux workflow](../.github/workflows/ci.yml) exercises PowerShell 7.4.20 and 7.6.6 with tmux 3.3a and 3.7c. Check the run for the commit you use; a green older commit does not verify newer code. |
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

Optional features can need a newer release than this floor. Their
requirements belong to the cmdlet that needs them and are listed with the
feature rather than raised for the whole module.

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
