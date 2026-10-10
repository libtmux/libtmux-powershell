# Event stream pressure benchmark

This benchmark checks loss accounting when native tmux notifications exceed a
one-event control queue. It does not compare watch latency with polling or
capture: a snapshot of the final window name cannot reproduce the sequence
of rename notifications or report which events were dropped.

One installed `LibTmux` package and one owned tmux session, window, and pane
serve the entire run. The runner reuses a control connection with
`ControlModeEventBufferCapacity = 1` and drains its initial notification.
Each pressure cell sends either eight or sixteen serial `rename-window`
commands with distinct names. `Watch-TmuxEvent` then reads the loss record
and the retained final notification. Every sample requires
`produced = delivered + dropped`, a cumulative loss count consistent with
the previous sample, and a final event name equal to the window name read
back from native tmux. A one-second completion bound prevents a missing
notification from leaving the watcher active indefinitely.

Build and package the PowerShell module using the
[contributor guide](../.github/CONTRIBUTING.md#setup). The supplied
`LibTmux.0.1.0-alpha2.nupkg` must contain a complete, internally consistent core
dependency. Run the negative controls and two-round installed-package smoke
first:

```console
$ pwsh -NoLogo -NoProfile -File benchmarks/EventStream.Tests.ps1 \
    -PackageRoot artifacts/local-build
```

Run three warmup and twenty sample rounds per burst size:

```console
$ pwsh -NoLogo -NoProfile -File benchmarks/EventStream.ps1 \
    -PackageRoot artifacts/local-build \
    -OutputPath artifacts/benchmarks/event-stream.json
```

The runner refuses to overwrite an existing report. `-TmuxBinaryPath`
selects a specific executable. The report retains every produced, delivered,
and dropped count, both observed events, the native final name, and raw
production and drain times. It reports medians and p95 only with at least
twenty samples per cell. Import, first-use work, control connection, and
disconnection are separate from sampled times. Versions, hashes, host details,
and `sourceDirty` identify the run. Package-only checks record
`sourceProvenance: unverified`; pass `-ReviewRoot` from a clean-source bootstrap
to verify the inspected .NET feed and staged module bytes. A PASS report is
written only after the borrowed control client disconnects and the owned
fixture and extracted package are removed.

The 8- and 16-command cells are pressure points on the same queue. The owned
fixture disables automatic window renaming before control attachment so shell
startup cannot add an unrelated rename to a measured burst. Positive drops
and the configured capacity of one imply a high-water mark of one. The runner
does not sample queue occupancy or the time it became full. Cell timings cover
serial command production and a bounded watcher drain; they do not measure
sustained stream throughput or justify a speed ratio.
