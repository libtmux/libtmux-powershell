# Benchmarks

Both runners extract the supplied PowerShell package into a temporary directory
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

Control-mode transport and command dispatch have a separate workload below.
Standalone C# process startup, concurrent/async acquisition, streaming
notifications, mutation throughput, and larger server shapes remain unmeasured.
They require their own correctness checks and raw distributions.

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

The workload measures serial read-only commands. Concurrent commands, async
client use, streaming notifications, mutation throughput, and scale are open.
