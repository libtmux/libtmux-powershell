# Changelog

## Unreleased

### What's new

#### New module: `LibTmux`

Automate sessions, windows and panes through PowerShell pipelines using
native libtmux for .NET objects. Capture and filter object graphs locally,
store structured queries, and inspect plans for fresh source queries. (#1)

- Compose ordered command chains or reuse a control client. Run pane
  commands with exit results, wait for readiness text, and consume bounded
  event streams that disclose loss. (#1)

#### New module: `LibTmux.Workspace`

Discover, import and validate YAML/JSON workspaces, review plans with
`-WhatIf`, and apply the reviewed actions. Inspect failure journals,
request owned compensation, and export captured sessions. (#1)

### Documentation

- Add executable object-graph, HTTP readiness, concurrency and workspace
  examples, installed cmdlet help, and configuration guides for the
  separately installed .NET MCP server. (#1)
- Add reproducible benchmarks for startup, queries, command transports and
  streams, with workload checks and raw measurements. (#1)

### Development

- Add a source bootstrap that builds both modules against inspected
  shared-core packages using an isolated local feed. Linux installed-package
  checks cover PowerShell 7.4 and 7.6; macOS checks remain advisory. (#1)
