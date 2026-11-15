# release-artifacts

Binds a Gallery release to the packages that CI tested. The release workflow
calls [`ci.yml`](../../.github/workflows/ci.yml) at scope `full`, then runs
`ReleaseArtifacts.ps1` to read that run from the GitHub API and write a receipt.
Only [`release.yml`](../../.github/workflows/release.yml) runs it, with
`GH_TOKEN`.

It refuses unless all of these hold:

- The run is this repository's `release.yml` run on `master`, started by a
  dispatch, still in progress, at the commit being released.
- Every job of the full-scope CI, named `ci / <job>`, completed successfully in
  this attempt at that commit, and the one `gallery` job is still running. The
  required names come from [`matrix.json`](../plan-matrix/matrix.json) through
  the planner, so a run that covered only the edges cannot pass.
- Exactly one unexpired `port-package` artifact exists, with a SHA-256 digest,
  and it was uploaded by this run at that commit.

On success it writes the receipt, which names the artifact and the jobs, and
appends `artifact_id` to the `GITHUB_OUTPUT` file for the download step.

## Tests

```console
$ pwsh -NoLogo -NoProfile -File \
    scripts/release-artifacts/tests/ReleaseArtifacts.Tests.ps1
```

The test accepts a trusted run, then changes the run, the jobs and the artifacts
one way at a time and expects each change refused.
