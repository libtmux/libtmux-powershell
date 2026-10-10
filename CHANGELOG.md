# Changelog

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
