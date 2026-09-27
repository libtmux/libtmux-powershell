# Complete pane payload observation

This benchmark measures when two installed libtmux for PowerShell paths observe
the **same complete multiline pane payload**. Each round writes one
display-safe ASCII block to an owned pane terminal. A persistent
`Watch-TmuxEvent` client accumulates output fragments; a separately armed
`Get-TmuxPaneContent -History -Raw` poller reads the rendered pane. Both must
contain the exact block before the round enters the report.

Build the module package with the
[contributor guide](../.github/CONTRIBUTING.md#setup). Run the negative controls
and a two-sample installed-package smoke first:

```console
$ pwsh -NoLogo -NoProfile -File benchmarks/StreamPayload.Tests.ps1 \
    -PackageRoot artifacts/local-build
```

Then record one first call, three warmups, and twenty raw timed samples. The
runner refuses to overwrite a report:

```console
$ pwsh -NoLogo -NoProfile -File benchmarks/StreamPayload.ps1 \
    -PackageRoot artifacts/local-build \
    -OutputPath artifacts/benchmarks/stream-payload.json
```

Use `-TmuxBinaryPath` to choose a tmux executable. Pass `-ReviewRoot` with a
clean-source bootstrap directory to verify its package receipt and inspected
.NET package feed. Without it, the report marks source provenance
`unverified`. The [package identity checks](PackageIdentity.Tests.ps1)
document that boundary.

Each block has unique begin and end markers and twelve body lines. The writer
sends the block plus LF in one write. Timing starts immediately before that
write. Event completion is the first callback containing the end marker after
fragment accumulation. Capture completion is the first poll containing the
end marker. The check extracts one block from each observation and compares
both with the expected text before recording either duration. It rejects
missing, truncated, reordered, duplicated, wrong-pane, late, or lossy
observations. The pure checks deliberately exercise those failures.

The only text transform is **CRLF to LF on event output**. Captured pane text
uses rendered lines and can include a prompt outside the compared block. The
two paths do not promise equal raw bytes; the report records produced,
unmodified event, and unmodified capture byte counts separately, plus SHA-256
hashes of the exact canonical block. It records event fragments, capture
attempts, first call, warmups, all timed samples, and median and nearest-rank
p95 only when at least twenty samples exist.

The watcher has event-count, per-event, and total-output bounds. A round has a
one-second completion deadline, a 64 KiB observation bound, and at most 100
capture attempts with a 10 ms interval. Screen and history reset, package
extraction, module import, control connection, and observer readiness occur
outside the timed write-to-completion window. Polling and observer scheduling
are included. The runner owns and removes its tmux socket, control client,
terminal writer, and temporary package extraction. A passing report is
written only after cleanup succeeds.

These measurements describe complete text observation for this payload on
one host. Compare raw distributions from repeated clean runs before making a
performance claim. For one-token visibility, see the
[output visibility benchmark](OutputLatency.md); for static capture sizes, see
the [capture-size benchmark](CaptureSize.md).
