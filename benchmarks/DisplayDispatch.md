# Display command dispatch benchmark

This benchmark compares six ways to request the same eight distinct
`display-message -p` replies from one owned tmux session, window, and pane.
Each command includes a literal sequence label and native session, window, and
pane IDs. The runner takes the expected replies from native tmux before timing.
Every lane must return those exact indexed replies. Serial and chained lanes
must also preserve command order. A native pane identity snapshot must remain
unchanged before and after every lane, including warmups and samples.

The lanes are direct native tmux invocation, serial `Invoke-TmuxCommand`, bounded
`Server.ExecuteCommandAsync`, serial `Invoke-TmuxControlCommand`, bounded
`IControlModeSession.SendAsync`, and one `Invoke-TmuxChain` call. The concurrent
lanes submit at most four commands per wave by default. They match replies by
submitted index and record the order in which completed tasks were reaped.
That observed order can differ from submission order; simultaneous completions
may appear in submission order. The native lane starts one tmux client process
per command through the owned fixture helper. The chain returns one merged
output stream.

Build and package the PowerShell module using the
[contributor guide](../.github/CONTRIBUTING.md#setup). The runner checks the
supplied `LibTmux.0.1.0.nupkg` against its embedded core version and assembly
hashes, extracts it into a temporary directory, imports that installed
artifact, and owns its tmux socket. Run the negative equality controls and a
two-round live smoke first:

```console
$ pwsh -NoLogo -NoProfile -File benchmarks/DisplayDispatch.Tests.ps1 \
    -PackageRoot artifacts/local-build
```

The check also sends an invalid pane target at command index three. Serial
callers stop and skip the tail; bounded concurrent callers retain outcomes by
submitted index, including commands already in flight. A chain exposes one
aggregate failure with merged prefix output, so its result alone cannot
identify every command's status. The check verifies the prefix and tail
effects in native tmux and leaves the borrowed server running.

Run the default three warmup and twenty sample rounds:

```console
$ pwsh -NoLogo -NoProfile -File benchmarks/DisplayDispatch.ps1 \
    -PackageRoot artifacts/local-build \
    -OutputPath artifacts/benchmarks/display-dispatch.json
```

`-TmuxBinaryPath` selects a specific tmux executable. `-MaxConcurrency`
sets the bound from one to eight. The report refuses to overwrite a prior
file. It records every reply, submission and observed completion order, pane
state before and after each lane, raw elapsed nanoseconds, medians, and p95
only when there are at least twenty samples. Import, first-use calls, control
connection, and disconnection have separate timings. The package, tmux,
benchmark source, host, and source checkout are identified by versions and
hashes; `sourceDirty` marks a checkout with unrelated edits too. Package-only
runs report `sourceProvenance: unverified`. Pass `-ReviewRoot` with a
clean-source bootstrap directory to verify the inspected .NET feed and staged
PowerShell build; that reports `sourceProvenance: verified` with both source
revisions.

The control client is reused during samples. Native timings include the owned
helper's process launch and capture overhead along with tmux. Disconnect removes
the client while leaving the borrowed session and daemon alive. The owned tmux
fixture and extracted package are removed even if a lane fails. These timings
cover end-to-end PowerShell API paths on one host, with separate direct core
calls for concurrency; compare raw distributions across repeated clean runs
before drawing a performance conclusion.
