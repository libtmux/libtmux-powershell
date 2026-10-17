# Changelog

## 0.1.0-alpha3 - Unreleased

### Breaking changes

#### Require tmux 3.3a or newer

Both modules now build on libtmux for .NET 0.0.0-alpha.22, which checks the
daemon's version before it sends any command. It refuses a daemon older than
3.3a, or one whose version it cannot read, with `TmuxVersionTooLowException`
before anything changes, and a daemon older than 3.2, which cannot report a
version, gets the same refusal. Reads return that error instead of an empty
result. The refusal says to upgrade tmux and restart the tmux server, or to
install `LibTmux` `0.1.0-alpha2`, the last release that accepts older tmux.
`Invoke-TmuxCommand` and `Invoke-TmuxChain` refuse to run if the daemon was
replaced by one below the floor after the check, and `Invoke-TmuxCommand
kill-server` against an endpoint with no daemon is a no-op. (#21)

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

### Documentation

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

#### New module: `LibTmux.Workspace`

Import YAML/JSON workspaces, resolve file-relative paths, preview planned
effects with `-WhatIf` and apply reviewed actions. Inspect failure and cleanup
journals, export captured sessions and convert workspace declarations. (#1)

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
