# Benchmarks

The runners extract the supplied PowerShell package into a temporary directory
and use an owned tmux socket. They write raw JSON distributions and make no
speedup claim from one host.

## Pane enumeration

This benchmark measures three ways to get pane IDs from one owned tmux server:
the native `tmux list-panes` command, the installed `Get-TmuxPane` cmdlet, and
the LibTmux .NET snapshot API called directly from the PowerShell host. The
third lane is a **hosted core** baseline, not a standalone C# process.

Build and package the modules as described in the
[contributor guide](../.github/CONTRIBUTING.md#setup). Then run a serial
sample. The runner removes its temporary package and socket after the run. It
refuses to overwrite an existing report.

```console
$ pwsh -NoLogo -NoProfile -File benchmarks/PaneEnumeration.ps1 \
    -PackageRoot artifacts/local-build \
    -OutputPath benchmarks/results/panes.json
```

Use `-TmuxBinaryPath` to select a specific tmux executable. The report records
the actual tmux version, its executable hash, the package hash, PowerShell and
.NET runtime versions, assembly identities, source commit, benchmark source
hashes, exact lane commands, and whether the checkout had tracked or untracked
changes before writing the report. It includes module import time, one
first-use call per lane, warmups, and every timed sample. The default
is three warmup rounds and twenty sample rounds. Each round rotates lane order.
The sample distribution excludes package extraction, import, and fixture setup.

Every call must return the same sixteen distinct pane IDs. A mismatch stops
the run before it writes a passing report. Run the correctness control, which
deliberately supplies unequal IDs before taking a small live sample:

```console
$ pwsh -NoLogo -NoProfile -File benchmarks/PaneEnumeration.Tests.ps1 \
    -PackageRoot artifacts/local-build
```

The native lane starts a tmux client for each listing. The cmdlet and hosted
core lanes acquire a complete pane-depth snapshot, then project pane IDs.
These are end-to-end API-path costs for the same answer, not identical internal
work. First-use calls run in fixed order after import, so treat them as startup
observations rather than a cross-lane cold-start comparison. The report's p95
uses nearest rank and appears only with at least twenty samples. Keep raw
samples when comparing runs; do not infer a speedup from a single noisy host.

Control-mode transport, command dispatch, query selection, and event pressure
have separate workloads below. The [standalone C# baseline](StandaloneCore/README.md)
separates fresh-process startup from capture in a reused .NET process.
Mutation throughput and scaling across multiple server sizes remain
unmeasured.

## Fresh PowerShell startup

The [cold PowerShell benchmark](ColdPowerShell/README.md) starts a new `pwsh`
process for every observation. It separates launch-to-exit time from module
import, server construction and the first sixteen-pane snapshot, checking the
same native pane IDs in every child. Its first run and warmups are recorded
apart from the timed distribution.

## Command transport

This workload runs `display-message -p '#{session_name}'` against one owned
session through native tmux, the process-backed `Invoke-TmuxCommand` cmdlet,
and `Invoke-TmuxControlCommand` on one reused control client. Every reply must
be exactly `fixture`; the runner checks that disconnect leaves the borrowed
session and daemon alive and removes the control client.

```console
$ pwsh -NoLogo -NoProfile -File benchmarks/CommandTransport.ps1 \
    -PackageRoot artifacts/local-build \
    -OutputPath benchmarks/results/command-transport.json
```

The report records package, tmux, benchmark source, and host provenance. It
separates module import, control connection, first-use calls, warmups, timed
samples, and control disconnection. The default is three warmup rounds and
twenty sample rounds in rotating lane order. Connection setup is excluded
from the control command samples, so use the separate connection time when
assessing short-lived clients. First-use calls run in fixed order and are not
a cross-lane cold-start comparison.

Run the unequal-reply control and a small owned-tmux smoke before interpreting
a report:

```console
$ pwsh -NoLogo -NoProfile -File benchmarks/CommandTransport.Tests.ps1 \
    -PackageRoot artifacts/local-build
```

The workload measures serial read-only commands. The
[display dispatch benchmark](DisplayDispatch.md) compares serial, bounded
concurrent, and chained paths using eight distinct replies. Streaming
throughput and mutation throughput remain open.

## Linked pane query selection

The [query selection benchmark](QuerySelection.md) selects one pane ID across
three placements of a linked window. It checks the same complete graph and
placement identities for native `Where-Object`, structured local selection,
and each admitted `Never`, `Auto`, or `Require` source-query mode. Local
filtering reuses one snapshot; source-query timing includes fresh acquisition.
The report keeps those cost scopes separate.

## Event stream pressure

The [event stream benchmark](EventStream.md) sends eight- and sixteen-rename
bursts into a one-event control queue. It checks the reported loss count,
retained final notification, and native final window name in every sample.
This is a queue-pressure test; it does not compare notification history with
polling or capture.

## Live output visibility

The [output visibility benchmark](OutputLatency.md) sends each unique token
once to an owned pane and times when a persistent control watcher and an
independently armed rendered-capture poller first observe it. Every round
checks the token, pane ID, event loss and cleanup. The 10 ms capture interval
and both observers' scheduling are part of the measured paths.

The [complete payload benchmark](StreamPayload.md) writes one multiline block
to the pane and requires the accumulated event output and rendered capture to
match the full canonical text. It records raw byte counts, fragment and poll
counts, and both completion times; it does not claim raw byte parity.

## Capture sizes

The [capture-size benchmark](CaptureSize.md) compares native complete-history
capture with `Get-TmuxPaneContent -History -Raw` for three fixed payloads. It
checks every payload line and exact lane equality before recording raw samples.

## Wait cancellation resources

The [wait-resource benchmark](ResourceCancellation.md) measures timeout and
pipeline-stop withdrawal on one owned server. It verifies native client exit,
the next channel signal, process counts, and topology preservation, while
recording PowerShell, daemon, and client resident memory. The two lanes have
different triggers and error contracts; the report does not give a speed ratio.

## Two endpoints

The [endpoint-pair benchmark](EndpointPair.md) reads one identity from each of
two owned tmux sockets. It compares native serial, installed cmdlet serial,
and two installed cmdlets in flight. Each result must match its socket's
identity before timing is accepted; completion order is recorded separately
from submission order.

## Idle control resources

The [idle-control benchmark](IdleControl.md) observes equal-length intervals
before, during and after one control connection. It records CPU time, resident
memory, process-wide managed allocation and exact owned client/process counts.
Its fixed phase order does not establish a causal idle cost.
