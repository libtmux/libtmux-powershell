# Fresh PowerShell startup

How long does a new `pwsh` process take to import libtmux for PowerShell and
read its first pane snapshot? This runner creates one owned tmux server with
four windows and sixteen panes. It launches a new `pwsh -NoProfile` process for
every observation. Each child imports the extracted package, constructs a
server handle, reads pane IDs with `Get-TmuxPane`, and exits.

Build the candidate package as described in the
[contributor guide](../../.github/CONTRIBUTING.md#review-package-builds).
From PowerShell in the repository root, run the negative controls and an
installed-package smoke. The hash is read from the exact archive under test;
the runner does not import product code from the source tree.

```powershell
$nupkg = 'artifacts/local-build/LibTmux.0.1.0-alpha1.nupkg'
$test = @{
    PackageRoot = 'artifacts/local-build'
    ExpectedPackageSha256 = (Get-FileHash $nupkg -Algorithm SHA256).Hash
}
./benchmarks/ColdPowerShell/Tests.ps1 @test
```

Collect twenty timed fresh processes after one first observation and two
untimed warmups. Choose an output path that does not exist yet.

```powershell
$nupkg = 'artifacts/local-build/LibTmux.0.1.0-alpha1.nupkg'
$run = @{
    PackageRoot = 'artifacts/local-build'
    ExpectedPackageSha256 = (Get-FileHash $nupkg -Algorithm SHA256).Hash
    OutputPath = 'artifacts/benchmarks/cold-powershell.json'
}
./benchmarks/ColdPowerShell/Run.ps1 @run
```

`-TmuxBinaryPath` selects the tmux executable. `-SampleRounds` defaults to
twenty and accepts 1–60; `-WarmupRounds` defaults to two and accepts 0–5.
The run has one eight-minute cancellation budget. It removes its own socket
and package extraction on success or failure and never addresses the default
tmux server.

The JSON report keeps each parent's process launch-to-exit time and the
child's separate module import, server construction, and first snapshot times.
The first observation and warmups are separate from timed samples. Package
extraction and fixture setup are recorded separately. Parent launch timing
includes PowerShell startup, script execution, result serialization, and
process exit; the child intervals are subsets, not independent costs to add
to the parent time. The report also records package, assembly, PowerShell,
tmux, source, and runner identities, plus source-tree dirtiness. Package-only
checks report `sourceProvenance: unverified`. Pass `-ReviewRoot` from a
clean-source bootstrap to verify the inspected .NET feed and staged PowerShell
build; that reports `sourceProvenance: verified` with both source revisions.

Every child must return the sixteen native pane IDs from the owned socket.
The negative control feeds wrong, duplicate, and missing IDs to that check.
The runner checks the native topology again after sampling and writes a
passing report only after cleanup. These samples describe one machine and
one topology; compare raw distributions and whole-command wall time before
drawing performance conclusions.
