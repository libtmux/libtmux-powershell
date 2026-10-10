# Linked pane query benchmark

This benchmark selects one pane ID across two linked-window graph sizes. It
builds each size on a separate owned tmux socket, then removes that fixture
before starting the next size. The same installed module package is reused.

| Shape | Sessions | Unique windows | Added links | Window placements | Unique panes | Pane placements |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Baseline | 3 | 9 | 2 | 11 | 27 | 33 |
| Expanded | 5 | 25 | 4 | 29 | 75 | 87 |

The selected window is placed once in every session, so the target pane has
three or five placement identities. Native `list-sessions`, `list-windows -a`
and `list-panes -a` supply the full graph identity reference. Every captured
graph must match all native session IDs, window placements, pane placements,
linked-session counts and parent references. Equal counts alone do not pass.

Within each size, `Where-Object` and `Select-TmuxPane` filter the **same
captured snapshot**. The source-query cells, `Never`, `Auto`, and `Require`,
acquire fresh complete snapshots from the same unchanged topology. Each source
mode joins the timed run only after its plan and result match the reference
placements and full graph. Unsupported modes appear in that size's `gaps` and
make the report `PARTIAL`. A local filter sample excludes snapshot capture;
a source-query sample includes acquisition. These are different cost scopes,
so the report does not calculate a cross-scope speed ratio.

Build and package the module using the
[contributor guide](../.github/CONTRIBUTING.md#setup). The runner validates
the supplied `LibTmux.0.1.0-alpha1.nupkg` against its embedded core version and
assembly hashes. Run same-count wrong-identity controls and a two-round
installed-package smoke:

```console
$ pwsh -NoLogo -NoProfile -File benchmarks/QuerySelection.Tests.ps1 \
    -PackageRoot artifacts/local-build
```

Run three warmup and twenty sample rounds per admitted lane in both sizes:

```console
$ pwsh -NoLogo -NoProfile -File benchmarks/QuerySelection.ps1 \
    -PackageRoot artifacts/local-build \
    -OutputPath artifacts/benchmarks/query-selection.json
```

`-TmuxBinaryPath` selects the executable to measure. The report's `shapes`
array keeps each size's native graph identities, admitted lanes, plan
pushdown/residual decisions, first calls, warmups, raw samples, median and
p95. The p95 appears only with at least twenty samples per lane. The shared
provenance records package and source hashes, checkout dirtiness, tmux version,
runtime identity, setup and import timing. Package-only runs report
`sourceProvenance: unverified`. Pass `-ReviewRoot` with a clean-source
bootstrap directory to verify the inspected .NET feed and staged PowerShell
build; that reports `sourceProvenance: verified` and identifies the module
source separately from the benchmark runner checkout.

The runner refuses to overwrite a report. It writes PASS or PARTIAL only
after removing both owned tmux fixtures and the extracted package. A single
host run does not establish a scaling ratio; compare raw distributions across
repeated clean runs before drawing a performance conclusion.
