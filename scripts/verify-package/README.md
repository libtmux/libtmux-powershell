# verify-package

Checks that the packages a CI job downloaded are the bytes the `port` job
packed, before a suite installs them.

`VerifyPackage.ps1` reads `package-evidence.json` in the package directory and
exits 1 unless it lists at least one package and each listed file exists with
the recorded SHA-256. With `-ExpectedTmux` it also exits 1 when the first
`tmux` on `PATH` is another executable, so a suite cannot run against a tmux
the job did not build.

```console
$ pwsh -NoLogo -NoProfile -File scripts/verify-package/VerifyPackage.ps1 \
    -PackageRoot build/package
```

## Tests

```console
$ pwsh -NoLogo -NoProfile -File \
    scripts/verify-package/tests/VerifyPackage.Tests.ps1
```

The test accepts matching packages and refuses a changed file, a missing file,
empty evidence, a missing evidence file and a `PATH` whose first tmux is not the
expected one.
