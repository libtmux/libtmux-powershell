# Two owned tmux endpoints

`EndpointPair.ps1` reads the same tmux identity format from two independently
owned sockets, each with one session, window, and pane. Three lanes issue one
read per endpoint: the owned native tmux helper serially, the installed
`Invoke-TmuxCommand` serially, and two installed cmdlets concurrently in
dedicated runspaces. The concurrent lane has a hard cap of two in-flight
commands. Every reply must match its socket's native identity, and both
identities must remain unchanged after every lane.

Run the equality negative controls and two-round installed-package smoke:

```console
$ pwsh -NoLogo -NoProfile -File benchmarks/EndpointPair.Tests.ps1 \
    -PackageRoot artifacts/local-build \
    -TmuxBinaryPath /usr/bin/tmux
```

Collect 20 serial rounds per lane for a descriptive p95:

```console
$ pwsh -NoLogo -NoProfile -File benchmarks/EndpointPair.ps1 \
    -PackageRoot artifacts/local-build \
    -TmuxBinaryPath /usr/bin/tmux \
    -OutputPath artifacts/benchmarks/endpoint-pair.json
```

The runner extracts the exact `LibTmux.0.1.0.nupkg`, validates its embedded
core version and assembly hashes, and records the source checkout,
runner/check hashes, package and tmux binary hashes, runtime, and assembly
identities. Package-only runs report `sourceProvenance: unverified`. Pass
`-ReviewRoot` with a clean-source bootstrap directory to verify the inspected
.NET feed and staged PowerShell build; that reports `sourceProvenance: verified`
with both source revisions. Package import, creation of both owned daemons, and
opening both runspaces have separate timings. First calls and warmups are
separate from the 20 raw samples per lane. Samples retain endpoint-indexed
replies, native state before and after, submission order, and completion order
reaped by `WaitAny`. Already completed commands can appear in index order
regardless of which finished first. Cleanup verifies both servers and sessions
remained live before their owned fixtures were removed.

Native samples include the `Invoke-OwnedTmux` PowerShell helper; cmdlet samples
include their PowerShell invocation overhead. This is a two-endpoint result
and timing observation on one host, without a speedup claim or a scaling
curve. Larger endpoint counts, persistent control connections, CPU, RSS,
allocation, and queue pressure remain unmeasured here.
