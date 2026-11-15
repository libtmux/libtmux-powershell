# review-dependencies

Pins the three shared libtmux for .NET packages to a disposable review build, so
a change to the shared source can be tested before it is published. Only
[`eng/BootstrapReview.ps1`](../../eng/BootstrapReview.ps1) runs it, in its
disposable clone of this repository. The clone also runs the .NET review
recipe, which stays Python and belongs to libtmux for .NET.

`ReviewDependencies.ps1` has three commands:

- `version -RunId N -Attempt N` prints a review version: the shared pin in
  `Directory.Packages.props`, which must be a prerelease, plus `.ci.N.N`.
- `prepare -Version V -Baseline DIR` saves both committed
  `packages.lock.json` files under `DIR` and rewrites the three shared
  `PackageVersion` pins to `[V]`.
- `verify -Version V -Baseline DIR` checks that the rebuilt locks resolve `V`
  for each shared package, and that they match the baseline except for the
  review version and the shared packages' own content hashes.

Each command exits 1 with the reason when it refuses. For example, from a
clone:

```console
$ pwsh -NoLogo -NoProfile -File \
    scripts/review-dependencies/ReviewDependencies.ps1 \
    version \
    -RunId 123 \
    -Attempt 1
```

## Tests

```console
$ pwsh -NoLogo -NoProfile -File \
    scripts/review-dependencies/tests/ReviewDependencies.Tests.ps1
```

The test prepares a scratch checkout and accepts review hashes only: it refuses
a changed third-party hash, locks that do not resolve the review version,
mismatched pins, a version that does not extend the pin, and an existing
baseline.
