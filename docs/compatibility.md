# Compatibility

This source checkout targets PowerShell 7.4 and .NET 8. The Linux workflow
tests the specific PowerShell and tmux versions below; other combinations
remain unverified. The modules are not yet published to PowerShell Gallery.
Both pin [libtmux for .NET](https://github.com/libtmux/libtmux-dotnet); build
them together from the [install guide](../README.md#install-from-source).

| Environment | Contract |
| --- | --- |
| Linux x64 | The [Linux workflow](../.github/workflows/ci.yml) exercises PowerShell 7.4.20 and 7.6.6 with tmux 3.2a through 3.7c. Check the run for the commit you use; a green older commit does not verify newer code. |
| WSL2 | Run PowerShell and tmux inside the same Linux environment. The Windows host's PowerShell process is outside this contract. |
| macOS | Intel and Apple Silicon have an advisory [eight-cell trial](../.github/workflows/macos-trial.yml). Suite failures appear in its job summaries and artifacts without failing the trial check; they do not establish support. |
| Native Windows and psmux | Outside this port's scope. |

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
