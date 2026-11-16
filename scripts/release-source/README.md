# release-source

Resolves the commit a Gallery release publishes and checks the release tag
against it, before the release downloads or publishes anything. Only
[`release.yml`](../../.github/workflows/release.yml) runs it, in a checkout of
the commit being released.

`ReleaseSource.ps1` takes the commit of the run and an optional tag. It
appends `commit=<sha>` to the `GITHUB_OUTPUT` file, and exits 1 with the reason
when:

- the tag is not named `v0.1.N` or `v0.1.0-alphaN`;
- the tag is missing or lightweight, because a release tag is annotated;
- the tag points at another commit than the one being released;
- the commit is not a full lowercase SHA.

```console
$ pwsh -NoLogo -NoProfile -File \
    scripts/release-source/ReleaseSource.ps1 \
    -Tag v0.1.2 \
    -Commit "$(git rev-parse HEAD)" \
    -GithubOutput "$(mktemp)"
```

## Tests

```console
$ pwsh -NoLogo -NoProfile -File \
    scripts/release-source/tests/ReleaseSource.Tests.ps1
```

The test builds a repository with an annotated tag, a lightweight tag and a
tag at an older commit. It accepts the annotated tag and refuses each other tag,
a malformed name and a short commit with the reason named, then runs the command
line and reads `commit=` from the output file.
