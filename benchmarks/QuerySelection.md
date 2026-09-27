# Linked pane query benchmark

This benchmark selects one pane ID across three placements of a linked window.
Its owned topology has three sessions, nine unique windows, two added window
links, eleven window placements, and thirty-three pane placements. Native
`list-panes` supplies the reference placement identities. Every captured
graph must retain all sessions, placements, and parent relationships.

`Where-Object` and `Select-TmuxPane` filter the **same captured snapshot**.
The source-query cells, `Never`, `Auto`, and `Require`, acquire fresh complete
snapshots from the same unchanged topology. Each source mode joins the timed
run only after its plan and result match the reference placements and graph.
Unsupported or non-equivalent modes appear in `gaps` and make the report
`PARTIAL`. A local filter sample excludes snapshot capture; a source-query
sample includes acquisition. These are different cost scopes, so the report
does not calculate a cross-scope speed ratio.

Build and package the module using the
[contributor guide](../.github/CONTRIBUTING.md#setup). The supplied
`LibTmux.0.1.0.nupkg` must contain the reviewed
`0.0.0-alpha.16.ps.2` core dependency. Run the negative placement and graph
controls with a two-round installed-package smoke:

```console
$ pwsh -NoLogo -NoProfile -File benchmarks/QuerySelection.Tests.ps1 \
    -PackageRoot artifacts/local-build
```

Run three warmup and twenty sample rounds per admitted cell:

```console
$ pwsh -NoLogo -NoProfile -File benchmarks/QuerySelection.ps1 \
    -PackageRoot artifacts/local-build \
    -OutputPath artifacts/benchmarks/query-selection.json
```

`-TmuxBinaryPath` selects an executable whose query capabilities you want to
measure. The report records its hash and version, each plan's pushed and
residual predicates, and reasons for excluded modes. It also records package
and source hashes, checkout dirtiness, setup, import, snapshot capture, query
construction, first-use calls, warmups, and every timed sample. The p95
appears only with at least twenty samples per cell.

The runner refuses to overwrite a report. It writes PASS or PARTIAL only
after removing its owned tmux fixture and extracted package. A single host
run describes these workloads and versions; compare raw distributions across
repeated clean runs before drawing a performance conclusion.
