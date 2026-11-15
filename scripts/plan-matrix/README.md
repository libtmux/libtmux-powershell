# plan-matrix

Plans the Linux CI jobs from one table. `matrix.json` lists the PowerShell
versions, the supported tmux releases with their pinned commits, tmux master,
and the releases the library refuses. `PlanMatrix.ps1` turns the table and the
event into the matrix that [`ci.yml`](../../.github/workflows/ci.yml) runs, so
the workflow lists no version.

`ci.yml` runs it twice, in the `plan` and `gate` jobs. A contributor runs it to
see what a dispatch would cover.

## Plan a run

```console
$ pwsh -NoLogo -NoProfile -File scripts/plan-matrix/PlanMatrix.ps1 \
    plan \
    -EventName workflow_dispatch \
    -Scope custom \
    -TmuxRef 3.6b,master
```

It prints the plan as JSON. With `-GithubOutput` and `-Summary` it appends the
workflow outputs and the job summary, as CI does. A plan the inputs cannot
justify exits 1 with `plan:` and the reason.

| Scope | What runs |
| --- | --- |
| `edges` | The oldest and the newest supported tmux, on every PowerShell. The default for a push, a pull request and a dispatch. |
| `full` | The whole table, tmux master and the refusal lanes. A Gallery release is bound to this run. |
| `custom` | Only the tmux refs named in `-TmuxRef`, at most eight. |

## Check the gate

`gate` reads the `NEEDS` environment variable, a `toJSON(needs)` document, and
exits 1 when a required job did not succeed or a refusal lane the plan left out
ran. A lane the plan scheduled must succeed, so a skipped one cannot pass.

## Tests

```console
$ pwsh -NoLogo -NoProfile -File scripts/plan-matrix/tests/PlanMatrix.Tests.ps1
```

The test has a check for each rule and a deliberate break for most of them: it
replaces the rule with its absence and requires the check to notice.
`MatrixManifest.Tests.ps1` checks that the compatibility guide, the README and
the macOS trial agree with `matrix.json`.
