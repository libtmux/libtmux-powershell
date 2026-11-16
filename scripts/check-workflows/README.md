# check-workflows

Reads the workflows as text and fails when they break a rule that no other
check sees. It needs no YAML parser. `ci.yml` runs it in the `port` job, and a
contributor runs it after editing a workflow:

```console
$ pwsh -NoLogo -NoProfile -File scripts/check-workflows/CheckWorkflows.ps1
```

It prints each problem and exits 1 when there is one. The rules:

- `ci.yml` takes its jobs from the plan: each matrix comes from a plan output,
  each lane runs only when the plan asks for it, no job lists a tmux version or
  a pinned commit, and an input reaches a script only through `env`.
- The job names match the set that
  [release-artifacts](../release-artifacts/README.md) requires, so renaming a
  job cannot break a release unnoticed.
- The gate needs every job and always runs. The debugging session is pinned to
  a commit, limited to the actor, bounded in time, and only in the matrix.
- `release.yml` calls the CI of its own commit at scope `full`, from `master`,
  and takes the packages from that run, not from a run someone passes in.
- No `run` line calls `apt` or `apt-get`, and no workflow starts Python or sets
  it up. The shared `apt-get` action runs apt, and `ci.yml` builds tmux with
  the shared `build-tmux` action, not `autogen.sh`.
- A `libtmux/.github` action is pinned to a full commit SHA.

## Tests

```console
$ pwsh -NoLogo -NoProfile -File \
    scripts/check-workflows/tests/CheckWorkflows.Tests.ps1
```

The test passes this repository's workflows, then plants each fault in a copy of
the text and expects the problem named. A rule that cannot fail would fail the
test.
