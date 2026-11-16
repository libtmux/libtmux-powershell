# install-powershell

Installs an official PowerShell release for a CI job. The job runs it with the
`pwsh` the runner already has, then uses the installed one for the tests, so a
leg tests the PowerShell version it names.

`InstallPowerShell.ps1` downloads `powershell-<version>-linux-x64.tar.gz` from
the PowerShell releases and refuses it unless its SHA-256 is the one in
[`matrix.json`](../plan-matrix/matrix.json). It extracts only after that check,
then runs the installed `pwsh` to confirm it reports the version.

The [macOS trial](../../.github/workflows/macos-trial.yml) installs the macOS
asset the same way. `-Platform osx-x64` or `osx-arm64` picks the asset, and
`-Sha256` gives its digest, because the table lists only the Linux digests.

```console
$ pwsh -NoLogo -NoProfile -File \
    scripts/install-powershell/InstallPowerShell.ps1 \
    -Version 7.4.20
```

The destination is `$RUNNER_TEMP/powershell` in CI and a `powershell` directory
under the temporary directory elsewhere. `-Destination` and `-Manifest` change
either. A version the table lacks exits 1.

## Tests

```console
$ pwsh -NoLogo -NoProfile -File \
    scripts/install-powershell/tests/InstallPowerShell.Tests.ps1
```

The test installs an archive it builds, refuses one whose digest differs
without extracting it, refuses a version the table lacks unless `-Sha256`
gives the digest, names the asset URL for each platform, and compares the
version of the running `pwsh`. The download itself runs in CI.
