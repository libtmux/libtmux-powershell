# Idle control connection resources

`IdleControl.ps1` samples one owned tmux socket in a fixed sequence: before a
control connection, while an installed `Connect-TmuxControl` client is attached,
and after `Disconnect-TmuxControl`. Each phase has the same number of warmup and
measured timer intervals. Native topology, client, and owned-process checks run
outside the timed intervals. The script removes its socket and extracted package
even when sampling fails.

Run the synthetic mismatch controls and a short installed smoke first:

```console
$ pwsh -NoLogo -NoProfile -File benchmarks/IdleControl.Tests.ps1 \
    -PackageRoot artifacts/local-build \
    -TmuxBinaryPath /path/to/tmux
```

Then run the default 20 samples per phase, each nominally 250 ms:

```console
$ pwsh -NoLogo -NoProfile -File benchmarks/IdleControl.ps1 \
    -PackageRoot artifacts/local-build \
    -TmuxBinaryPath /path/to/tmux \
    -OutputPath artifacts/benchmarks/idle-control.json
```

The JSON keeps every interval's actual duration, start/end CPU time and RSS for
PowerShell and the owned tmux daemon, start/end process-wide .NET allocation,
and the native control client's CPU/RSS while connected. It records native
client and owned-process counts at both ends of each phase, topology identity,
package and binary hashes, module IDs, source state, setup/connect timings, and
cleanup. Package-only runs verify archive and embedded assembly bytes and report
`sourceProvenance: unverified`. Pass `-ReviewRoot` from a clean-source bootstrap
to verify the inspected .NET feed and staged PowerShell build; that reports
`sourceProvenance: verified` with both source revisions. The report also hashes
the package identity helper. Median and p95 are descriptive summaries of 20
samples; smaller runs leave p95 null.

`GC.GetTotalAllocatedBytes(true)` includes the sampler and every managed thread
in this PowerShell process. RSS is a snapshot, not retained memory. The control
event buffer is configured to 16 entries, but this passive run cannot observe
queue depth, high-water mark, or event drops. Initial attach notifications may
remain buffered. The fixed before/during/after order and one host do not
establish a causal idle cost or a speed ratio.
