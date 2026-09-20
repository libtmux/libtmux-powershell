# libtmux for PowerShell

Native C# cmdlets over the LibTmux .NET core, with a separate workspace
module. This is a local alpha implementation; no release is published.

The current packages provide local endpoint construction, explicit connection
and snapshot acquisition, typed session/window/pane listing, creation and
removal, text and key input, capture, refresh, raw commands and workspace
YAML parsing. Remaining mutation
commands, complete workspace planning and the rest of the suite are under
development.

From an installed module, construct a handle for later operations:

<!-- example: read.endpoint -->
```powershell
LibTmux\New-TmuxServer -SocketName development
```

The result is a native `LibTmux.Server`. Constructing a handle does not own
the daemon or establish that it exists. Properties and default formatting
perform no tmux I/O.

[Read commands](docs/read.md) acquire native objects with exact selectors
and explicit owner parameters. Use `@(...)` for stable zero/one/many arrays;
ordinary `Where-Object` predicates filter captured objects locally.
[Capture and raw commands](docs/capture.md) describe rendered text, capture
flags, replacement refresh and mutation previews.
[Create sessions, windows and panes](docs/create.md) covers native owners,
detached defaults, split sizing, command strings and environment entries.
[Remove sessions, windows and panes](docs/remove.md) explains confirmation,
shared-window effects and native-owner deletion.
[Send input](docs/input.md) separates literal text from tmux key tokens,
including ordering, confirmation and partial failure.

Parse YAML without running its commands:

<!-- example: workspace.parse -->
```powershell
LibTmux.Workspace\Import-TmuxWorkspace -Yaml 'session_name: development'
```

The result is a native `LibTmux.Workspace.WorkspaceFile`. Parsing accepts
the current engine's subset; it does not yet implement the full workspace
contract. Install both modules at the same version. A conflicting loaded
LibTmux assembly requires a fresh PowerShell process.

The build targets PowerShell 7.4 and .NET 8. All currently implemented package
suites pass on Linux x64 with PowerShell 7.4.20 and 7.6.6, each on tmux 3.2a
and 3.7c. Checks include native installation, snapshots, input, executable
help and guides, cancellation and owned cleanup. macOS, the complete tmux
compatibility matrix and the full product remain unverified. Local packages
do not establish a supported release.

See [contributing](.github/CONTRIBUTING.md) for local build, packaging and
verification commands. The separately packaged
[LibTmux.Mcp tool](https://github.com/libtmux/libtmux-dotnet/tree/master/src/LibTmux.Mcp)
supplies the MCP product; this repository does not host another protocol engine.
