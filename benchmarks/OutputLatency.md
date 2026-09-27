# Live pane output visibility

This benchmark measures when one new pane output token becomes visible. It
sends a unique ASCII token to an owned `cat` pane for each round. A persistent,
borrowed `Watch-TmuxEvent` client and an independently armed
`Get-TmuxPaneContent -History -Raw` poller observe the same output. Both record
timestamps from the PowerShell process's monotonic clock.

The watcher must acknowledge a native rename notification before timing. The
capture poller must confirm that the token is absent before the send. Every
round checks the pane ID, accumulates output fragments until the full token
appears, rejects reported event loss, and requires the rendered capture to
contain that token. An observation must finish within one second. The runner
disconnects its control client and removes its owned socket and temporary
package extraction after sampling.

Build the module package using the
[contributor guide](../.github/CONTRIBUTING.md#setup).
Run the negative controls and a two-sample installed-package smoke:

```console
$ pwsh -NoLogo -NoProfile -File benchmarks/OutputLatency.Tests.ps1 \
    -PackageRoot artifacts/local-build
```

Run three warmups and twenty timed rounds. Choose an output path that does not
exist yet:

```console
$ pwsh -NoLogo -NoProfile -File benchmarks/OutputLatency.ps1 \
    -PackageRoot artifacts/local-build \
    -OutputPath artifacts/benchmarks/output-latency.json
```

`-TmuxBinaryPath` selects the tmux executable. The runner accepts the core
version recorded by the installed package; it does not require a fixed review
version. It checks the embedded assembly hashes and records the archive hash,
module and core identities, tmux version and binary hash, source state, first
call, warmups and every raw sample. Basic package checks report
`sourceProvenance: unverified`. Pass `-ReviewRoot` with a clean-source bootstrap
directory to check its receipt and inspected .NET package feed; only that
strict check reports `sourceProvenance: verified`. The
[package identity tests](PackageIdentity.Tests.ps1) cover the strict check and
reject a self-consistent repack from different core bytes.

Each sample includes the token, event fragment count, capture attempt count
and both visibility times. Median and p95 describe the twenty timed samples;
p95 is absent for smaller runs.

Timing starts before two owned `send-keys` calls: one sends literal text and
one sends Enter. Event time ends when the watcher sees the complete token;
capture time ends when a 10 ms poll finds it on the rendered screen. The
measurements include input dispatch, runspace scheduling, concurrent observer
load and the capture poll interval. They describe observed visibility for one
plain-text workload on one host. tmux may split output across events, and a
rendered capture is not a byte-exact output log. Compare raw distributions from
repeated clean runs before making a performance claim.
