# macos-trial

Records and reports one leg of the advisory
[macOS trial](../../.github/workflows/macos-trial.yml). `MacosTrial.ps1` has two
actions.

`provenance` runs after the leg installs PowerShell and builds tmux with
[build-tmux-macos](../build-tmux-macos/README.md), and exits 1 unless:

- the first `tmux` on `PATH` is the one built, and the core checkout is at the
  pinned revision;
- `core-dependencies.json` names the expected core package version;
- `package-evidence.json` lists exactly `LibTmux.<version>.nupkg` and
  `LibTmux.Workspace.<version>.nupkg` for its own version, and each file has
  the SHA-256 the evidence records, checked with
  [verify-package](../verify-package/README.md).

It then writes the record of what ran, with the digests of PowerShell and tmux,
the Homebrew versions and the packages, as `-Output`.

`report` runs after the suites, which the trial does not let fail the job. It
writes a one-line JSON record of the leg's suite outcomes to `-Output`, appends
a table to the job summary file, and prints a `::warning::` annotation when a
suite did not succeed.

```console
$ pwsh -NoLogo -NoProfile -File \
    scripts/macos-trial/MacosTrial.ps1 \
    report \
    -Runner macos-15 \
    -Powershell 7.4.20 \
    -Tmux 3.3a \
    -Output build/macos-cell.json \
    -VersionCheck success \
    -Features success \
    -Product failure \
    -Documentation success
```

## Tests

```console
$ pwsh -NoLogo -NoProfile -File \
    scripts/macos-trial/tests/MacosTrial.Tests.ps1
```

The test builds a package directory and a tmux on `PATH`, records the
provenance, and refuses a core checkout at another revision, another core
version, a different tmux, a third package, a renamed package, a changed package
and a missing package. It checks the record, the table and the warning, and runs
`report` as a command. The provenance command needs the packages of a trial
run, so it runs in the trial.
