# Capture size benchmark

This benchmark measures complete history capture from three panes on one
owned tmux socket. Each pane receives fixed 64-character lines, with 24,
256, or 1024 payload lines. The report records the actual rendered byte count
for each cell, since tmux screen padding can affect capture size.

The native lane runs `capture-pane -p -S -` through an owned tmux client. The
installed cmdlet lane runs `Get-TmuxPaneContent -History -Raw` on the selected
pane. The runner removes native trailing blank screen padding from this
fixture before comparing text. It verifies every payload line and exact
lane equality before timing, then checks equality after every warmup and
sample. A mismatch stops the run without writing a passing report.

Build and package the module using the
[contributor guide](../.github/CONTRIBUTING.md#setup). Supply the resulting
`LibTmux.0.1.0-alpha1.nupkg` as `-PackageRoot`. Run the unequal-text control and
two-round installed-package smoke:

```console
$ pwsh -NoLogo -NoProfile -File benchmarks/CaptureSize.Tests.ps1 \
    -PackageRoot artifacts/local-build
```

Run three warmup and twenty sample rounds per size and lane:

```console
$ pwsh -NoLogo -NoProfile -File benchmarks/CaptureSize.ps1 \
    -PackageRoot artifacts/local-build \
    -OutputPath artifacts/benchmarks/capture-size.json
```

`-TmuxBinaryPath` selects an executable to measure. The runner refuses to
overwrite a report. It records raw timing samples, medians, p95 with at least
twenty samples, fixture sizes and content hashes, package and benchmark
source hashes, tmux version and hash, runtime and assembly identities, and
source checkout dirtiness. The six cells run serially in rotating order.
Package extraction, import, fixture setup, and pane selection are outside
the timed samples. First calls include startup costs and run in fixed order.

These are end-to-end PowerShell API paths. The native lane includes the
benchmark's owned-process wrapper; it does not isolate tmux execution time.
The workload uses one socket and ASCII rendered text. It does not measure
multiple endpoints, concurrent capture, escape sequences, or binary output.
Keep the raw distributions and repeat runs on the same host before making a
performance claim.
