# Changelog

Notable changes to libtmux for PowerShell that span both modules: documentation,
development, packaging, and the notes that cover a whole release. A change to
one module is in that module's changelog:

- [`LibTmux`](module/LibTmux/CHANGELOG.md)
- [`LibTmux.Workspace`](module/LibTmux.Workspace/CHANGELOG.md)

The modules are released together at one version, so a release has a section in
each changelog.

## 0.1.1 - Unreleased

### Breaking changes

#### Pass no socket to tmux unless a variable is set

Both modules now build on libtmux for .NET 0.1.1. A server handle that names no
socket passes tmux neither `-L` nor `-S`, so tmux picks the server: the one
`TMUX` names inside a tmux pane, otherwise its default socket. Before,
`New-TmuxServer` with no parameter passed `-L default` and gave tmux no `TMUX`,
so a handle made inside a pane still reached the default socket.
`LIBTMUX_SOCKET_PATH` becomes `-S` and `LIBTMUX_SOCKET` becomes `-L`; the path
wins when both are set, a blank value counts as unset and `-SocketName` or
`-SocketPath` beats both. The handle reads the variables when it is made.
`LIBTMUX_SOCKET_NAME`, which 0.1.0 read, now selects nothing.

To keep code on a server of its own, pass `-SocketName` or `-SocketPath`, or
set `LIBTMUX_SOCKET` or `LIBTMUX_SOCKET_PATH`; code that set
`LIBTMUX_SOCKET_NAME` should set `LIBTMUX_SOCKET`. Confirmation and `-WhatIf`
text calls a handle with no socket "tmux-selected server", not "default tmux
endpoint". (#65)

#### Choose a socket for the 0.1.1 MCP tool

The separate `LibTmux.Mcp` tool, which the MCP guide and CI now install at
0.1.1, follows the same rule. With neither variable it drives the server tmux
picks, so an assistant started from a tmux pane works on the panes you are
using. It offers no `teardown` toolset and reports the selector `default`,
where 0.1.0 started a daemon on a `libtmux-mcp` socket of its own. With both
variables set the path wins, where 0.1.0 refused to start.

To keep an assistant on a server of its own, set `LIBTMUX_SOCKET` or
`LIBTMUX_SOCKET_PATH` in its configuration, as the guide shows. Unlike a
handle, the tool does not ignore a blank value: a blank `LIBTMUX_SOCKET` or
`LIBTMUX_SOCKET_PATH` stops startup, as `LIBTMUX_SOCKET_NAME` alone still does.
(#65)

### Bug fixes

- `Set-TmuxLayout` and `Get-TmuxWorkspacePlan` now refuse a JSON layout on a
  tmux older than 3.8 before applying the layout, raising
  `LibTmux.TmuxUnsupportedOnReleaseException` with `CapabilityId` `layout-json`
  and `SafeReleases` "3.8 or newer". Planning wraps it in a
  `WorkspaceFormatException`. Installed tmux releases behave as before: each
  one that refused a JSON layout still refuses it, and 3.8 applies it. (#51)
- Preserve blank lines in native help examples without displaying control
  characters.

### Development

- Run the test suites in a sandbox, so that a test, example or documentation
  check that names no socket cannot reach the tmux server you work in.
  `eng/Test.ps1` and each script that builds a handle remove `TMUX`,
  `TMUX_PANE` and every `LIBTMUX_SOCKET*` variable, point `TMUX_TMPDIR` at a
  private owner-only directory and refuse to run without it. When a run ends,
  any server left in that directory is stopped and fails the run. (#63)
- Add a `Socket` suite that starts a process for each rule of the no-socket
  default against a recording tmux, and shows that its check fails on calls
  that break each one. (#65)

### Documentation

- Say what a server handle passes tmux with no socket parameter, and which
  variable becomes `-S` and which `-L`, in the `New-TmuxServer` reference, the
  read guide, the README, the troubleshooting guide and the MCP guide, and show
  in CONTRIBUTING how to start a session by hand on a socket of your own. (#65)
- State first-use version requirements and distinguish polling, completion
  signals, version probes, control-client ownership and native table lookup.

## 0.1.0 - 2026-10-25

### Packaging

- Build, test and publish a final release. The package scripts and the
  release workflow now read the version from the module manifest, which has no
  `Prerelease` label, and `release.yml` accepts a `v0.1.N` tag as well as
  `v0.1.0-alphaN`.

### Documentation

- Install with plain `Install-PSResource -Name LibTmux` or
  `Install-Module -Name LibTmux`, without `-Version`, `-Prerelease` or
  `-AllowPrerelease`, and import without a pinned version.
- Number releases `0.1.N` from now on, starting with `0.1.0`, with no
  `-alpha` label unless the maintainer asks for one. The README and package
  READMEs now say that the API is not settled and to pin an exact version,
  and the contributor guide describes cutting a `0.1.N` release.
- Put the optional-features table first in the compatibility guide, link each
  capability to its evidence, and link `capabilities.json` from the README.
  State that the checks do not read a refused command nested in another
  command's text, and what each failure does on which release. (#39)
- Name the exception each refusal raises under the optional-features table,
  and link the raw-command help to the nested-command failures. (#40)

## 0.1.0-alpha3 - 2026-10-24

### Breaking changes

#### Require tmux 3.3a or newer

Both modules now build on libtmux for .NET 0.0.0-alpha.23, which checks the
daemon's version before it sends any command. It refuses a daemon older than
3.3a, or one whose version it cannot read, with `TmuxVersionTooLowException`
before anything changes, and a daemon older than 3.2, which cannot report a
version, gets the same refusal. Reads return that error instead of an empty
result. The refusal says to upgrade tmux and restart the tmux server, or to
install `LibTmux` `0.1.0-alpha2`, the last release that accepts older tmux.
`Invoke-TmuxCommand` and `Invoke-TmuxChain` refuse to run if the daemon was
replaced by one below the floor after the check, and `Invoke-TmuxCommand
kill-server` against an endpoint with no daemon is a no-op. (#21)

### Development

- Remove the pane text watcher and the literal command parser that worked
  around the earlier .NET package. (#22)
- Record the tmux release each optional feature needs in one registry, and write
  `capabilities.json` from it for the capabilities page of the documentation
  site. A test fails when the file and the registry differ. (#22)

### Documentation

- List the tmux release each optional feature needs in the compatibility guide,
  with what the checks leave out. (#22)
- Give the `LibTmux` and `LibTmux.Workspace` source directories a README and
  list each product on the repository page under a heading that links its
  directory. Link the first mention of each public cmdlet and native type to
  its libtmux.org page, and every MCP tool name to its tool page. Add the
  Claude Code and JSON registrations for the separate MCP tool.
- Section the repository and module READMEs by task. Each opens on a Quick
  start, names the cmdlet in each subsection heading, and closes with what the
  modules leave out and what they support. Move the PowerShellGet install
  commands to the compatibility guide. The README link check now fails a README
  that skips those sections or has a paragraph over 240 characters.

## 0.1.0-alpha2 - 2026-10-10

### Documentation

- Start with PowerShell Gallery installation, then follow the object-graph
  and workspace examples from installed modules. Documentation and image
  links use absolute URLs for Gallery imports; source-build instructions
  and the checkout quick start have their own section.

### Development

- Run the README quick start from the checkout root when verifying saved
  Gallery packages, and restore the caller's working directory afterward.

## 0.1.0-alpha1 - 2026-10-10

First alpha release of `LibTmux` and `LibTmux.Workspace`. APIs may change before
a stable release. Both modules build on
[libtmux for .NET 0.0.0-alpha.20](https://github.com/libtmux/libtmux-dotnet/releases/tag/v0.0.0-alpha.20).
Workspace requires `LibTmux` exactly `0.1.0-alpha1`.

### Documentation

- Follow executable object-graph, service-readiness, concurrency and workspace
  guides, native cmdlet help and a separately installed .NET MCP walkthrough.
  (#1)
- Reproduce startup, query, command-transport and streaming measurements with
  benchmark runners that validate their workloads and retain raw results. (#1)

### Development

- Build both modules over published libtmux for .NET packages with locked
  dependencies. Linux CI checks installed modules and executable documentation
  on PowerShell 7.4 and 7.6; macOS checks are optional. (#1)
- Install both modules as explicit Gallery prereleases, with Workspace pinned
  to the matching core alpha. Future releases default to the alpha line.
  (#11)
