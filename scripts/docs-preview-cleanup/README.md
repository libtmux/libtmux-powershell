# docs-preview-cleanup

Deletes the documentation preview of a closed pull request.
[`docs-preview-cleanup.yml`](../../.github/workflows/docs-preview-cleanup.yml)
runs it when a pull request closes, on the default branch's copy of the
scripts, so no pull request content runs with the cleanup role.

`DocsPreviewCleanup.ps1` has two actions:

- `eligibility` reads the pull request from the GitHub API with `GH_TOKEN` and
  appends `should_cleanup=true` to the `GITHUB_OUTPUT` file when it is closed.
  A closed event can be rerun after the pull request reopens, so the workflow
  reads the state again before it assumes the cleanup role. The script writes
  `should_cleanup=false` first and exits 1 when the number is not a positive
  integer or the response is not the pull request asked for, with a state
  other than open or closed.
- `delete` runs `aws s3 rm` on `s3://<bucket>/en/powershell/pr-<number>/`
  with `--recursive`, after the same number check.

```console
$ pwsh -NoLogo -NoProfile -File \
    scripts/docs-preview-cleanup/DocsPreviewCleanup.ps1 \
    eligibility \
    -Repository libtmux/libtmux-powershell \
    -Pr 12 \
    -GithubOutput "$(mktemp)"
```

## Tests

```console
$ pwsh -NoLogo -NoProfile -File \
    scripts/docs-preview-cleanup/tests/DocsPreviewCleanup.Tests.ps1
```

The test accepts a closed pull request and an open one, refuses each malformed
response and number, checks the preview prefix, and runs the command line on a
non-numeric number to see it exit 1 before it calls `gh` or `aws`. The two
calls run in CI when a pull request closes.
