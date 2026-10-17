# Changelog

## 0.1.0-alpha3 - Unreleased

### Breaking changes

#### Require tmux 3.3a or newer

Every cmdlet that talks to tmux checks the daemon's version first and
refuses a daemon older than 3.3a, or one whose version it cannot read, with
`TmuxVersionTooLowException` before anything changes. Reads return that error
instead of an empty result. `Invoke-TmuxCommand` and `Invoke-TmuxChain` also
refuse to run if the daemon was replaced after the check, a control
connection opened elsewhere is checked before it carries a command, and
`Invoke-TmuxCommand kill-server` against an endpoint with no daemon is a
no-op. (#21)

### Optional features

- Refuse features that need a newer tmux release for that cmdlet alone,
  before anything is sent, with `TmuxVersionTooLowException`: control clients
  (`Connect-TmuxControl`, `Watch-TmuxEvent` with a server and
  `Wait-TmuxPaneText`) need tmux 3.7, because short-lived control attaches
  can crash servers before 3.7 (measured on 3.2a and 3.6b);
  `Invoke-TmuxPaneCommand` and literal `delete-buffer -b` and
  `set-buffer -b -n` items need 3.4. Exactly 3.7 refuses `break-pane`
  without a name and `:` or `.` in session and window names, and exactly
  3.4 refuses `split-window -p`. Everything else stays available from
  3.3a. (#18)

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
