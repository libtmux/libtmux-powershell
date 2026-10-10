# Channel wait cancellation resources

`ResourceCancellation.ps1` observes two ways to withdraw a native
`Wait-TmuxChannel` waiter from one owned tmux socket. The timeout lane uses a
0.5-second command timeout; the pipeline-stop lane calls `BeginStop` after the
native wait client signals a start marker. Both must emit no success object,
retire the owned client process, leave the tmux topology unchanged, and allow
the next signal on that channel to be observed. Timeout must report
`OperationTimeout`; stop must
produce `PipelineStoppedException` without a cmdlet error. These are distinct
triggers and error contracts, so the report contains no speed ratio.

Run the negative controls and a two-round installed-package smoke first:

```console
$ pwsh -NoLogo -NoProfile -File benchmarks/ResourceCancellation.Tests.ps1 \
    -PackageRoot artifacts/local-build \
    -TmuxBinaryPath /usr/bin/tmux
```

Record 20 serial samples per lane for p95:

```console
$ pwsh -NoLogo -NoProfile -File benchmarks/ResourceCancellation.ps1 \
    -PackageRoot artifacts/local-build \
    -TmuxBinaryPath /usr/bin/tmux \
    -OutputPath artifacts/benchmarks/resource-cancellation.json
```

The runner extracts and imports the exact `LibTmux.0.1.0.nupkg`, validates its
embedded core version and assembly hashes, and records source, runner, package,
tmux, runtime, and assembly identities. Package-only runs report
`sourceProvenance: unverified`. Pass `-ReviewRoot` from a clean-source bootstrap
to verify the inspected .NET feed and staged PowerShell build; that reports
`sourceProvenance: verified` with both source revisions. The report also hashes
the package identity helper. The JSON keeps first calls, warmups, every raw
sample, and a 20-sample median/p95 for time from each lane's trigger to
completion.
The timeout trigger is `BeginInvoke`; the stop trigger is `BeginStop`.
Package import and fixture setup are timed separately. Each sample records
registration and result checks, native `list-clients` counts, owned-process
counts, the active wait client's PID and resident memory, and PowerShell and
daemon resident memory before, during, and after the wait.

Tmux `list-clients` does not enumerate unattached `wait-for` command clients on
the measured host; the native client PID and owned-process count establish
client-process liveness and retirement. The marker is sent before the native
wait command starts, so it does not prove the waiter has registered. Tmux does
not expose the channel queue depth. PowerShell memory includes the benchmark
harness and varies with garbage collection and host activity; these bounded
observations are not a leak verdict. The fixture, package extraction,
runspace, and every owned client are cleaned up on success or failure.
