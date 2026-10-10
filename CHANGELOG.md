# Changelog

## 0.1.0-alpha3 - Unreleased

- Retain accepted core owners when acquisition and rollback both fail before returning a result. `Get-TmuxScopeFailure -Pending` preserves the original and cleanup errors across runspaces; `Close-TmuxScope` retries the same captured authority.
- Bundle the inspected shared recovery dependency `0.0.0-ci.1791642867347.1994485671` for local review builds.


- Add `Start-TmuxServer` to start or reuse a daemon and return an ordinary server. Keep `New-TmuxServer` as borrowed endpoint construction.
- Make the imported quick start reusable without socket or cleanup scaffolding. Retain the previous program as `SessionCleanup.ps1` and test the unchanged ordinary source with external endpoint configuration.

- Add explicit owned server, session, window and pane creation, adoption and PowerShell script-block scopes. Cleanup survives pipeline cancellation, retains paired errors on the owner, and permits retry after a failed attempt.
- Add bounded `Find-TmuxServer` discovery and `Resolve-TmuxServer`, `Resolve-TmuxSession`, `Resolve-TmuxWindow` and `Resolve-TmuxPane` results that distinguish created ownership from borrowed reuse.
- Bundle the reviewed local .NET lifecycle build for these cmdlets; the module keeps its PowerShell 7.4 and .NET 8 minimums.

### What's new

- Construct `New-TmuxServer` with endpoint defaults in this order: explicit
  socket, `LIBTMUX_SOCKET_PATH`, `LIBTMUX_SOCKET_NAME`, `TMUX`, then tmux's
  named default. The handle captures the endpoint, child environment and
  executable lookup. `-ChildEnvironment` accepts copied overrides and null
  removals without changing the PowerShell host or tmux environment tables.
- Run `SessionCleanup.ps1` against those defaults. It removes its created
  session by ID on success or failure and retains body and cleanup exceptions.

### Development

- Restore exact .NET dependencies with committed locks. Use the source bootstrap for shared-library review builds.

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
