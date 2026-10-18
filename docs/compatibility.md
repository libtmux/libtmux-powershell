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
| Linux x64 | The [Linux workflow](../.github/workflows/ci.yml) exercises PowerShell 7.4.20 and 7.6.6 with tmux 3.2a and 3.7c. Check the run for the commit you use; a green older commit does not verify newer code. |
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
