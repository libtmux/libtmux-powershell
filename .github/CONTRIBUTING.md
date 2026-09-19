# Contributing

This repository contains the native cmdlet and package foundation for
libtmux for PowerShell. The full automation suite is under development.

Read [AGENTS.md](../AGENTS.md) for change discipline and [WRITING.md](WRITING.md)
for prose and commit conventions.

## Modules

The module exposes C# cmdlets built on the LibTmux NuGet package from
[libtmux for .NET](https://github.com/libtmux/libtmux-dotnet). Use these names
for the implementation:

| Surface | Name |
| --- | --- |
| Prose and documentation titles | libtmux for PowerShell |
| Gallery module and published folder | `LibTmux` |
| Manifest | `LibTmux.psd1` |
| Cmdlet project, assembly, and namespace | `LibTmux.PowerShell` |
| Cmdlet nouns | Singular `Tmux` nouns, such as `Get-TmuxSession` |
| Output types | LibTmux's own types, such as `LibTmux.Session` |
| Default views | `LibTmux.Format.ps1xml` |

The target baseline is PowerShell 7.4 with .NET 8 on Linux and macOS. Keep
module, folder, and manifest casing consistent. Export cmdlets explicitly and
do not export aliases that could shadow the `tmux` executable. Pin the bundled
LibTmux dependency to an exact version when a project is added.

Module versions will use plain three-part `0.x` versions without prerelease
labels, independently of the LibTmux NuGet version. Describe the module as
alpha in prose and record the bundled dependency version in release notes.
Local package artifacts do not establish publication or platform support.

## Setup

[.tool-versions](../.tool-versions) pins PowerShell and the .NET SDK.
[global.json](../global.json) enforces the effective SDK, including when
mise uses a shared dotnet launcher. Development pins do not establish tested
platform or tmux compatibility.

Install the pinned tools with mise from the repository root:

```console
$ mise install
```

The dependency source uses its own SDK pin. Build local NuGet packages from
an explicitly selected .NET checkout, restore locked dependencies, and stage
both PowerShell modules. Supply a checkout through the `CORE_SOURCE` shell
variable; do not build into a checkout another task is compiling concurrently.

```console
$ pwsh -NoLogo -NoProfile -File eng/Build.ps1 \
    -Restore \
    -PackCore \
    -CoreSource "$CORE_SOURCE"
```

The exact local dependency versions are in
[Directory.Packages.props](../Directory.Packages.props); these are not
published releases. Restore uses `build/nuget` and an isolated
`build/packages` cache.
The initial implementation depends on local .NET core fixes for linked-window
placements, strict session acquisition, captured pane fields and send-key
composition. A clean upstream checkout does not yet supply that complete
dependency. Keep the branch in draft until those source changes and their
reproducible package identity are available to reviewers; do not substitute
different source under the pinned local version. Packaging records the
selected revision, branch and source-file hashes beside the local packages.
Do not replace an immutable dependency package with changed source under the
same version. Bump its local suffix and update exact references and locks
with `-Restore -UpdateLock`; ordinary restore uses locked mode.

After restore, rebuild and stage without network access:

```console
$ pwsh -NoLogo -NoProfile -File eng/Build.ps1
```

Create local `.nupkg` module artifacts using PSResourceGet 1.1.1, included
with the baseline PowerShell installation. This does not publish them:

```console
$ PSModulePath="$PWD/build/Modules" pwsh -NoLogo -NoProfile -File eng/Package.ps1 \
    -DestinationPath artifacts/local-build
```

Execute fresh-process consumer checks from extracted packages:

```console
$ pwsh -NoLogo -NoProfile -File eng/Test.ps1 \
    -Suite Package \
    -PackageRoot artifacts/local-build
```

Verify native package-manager dependency resolution using a temporary local
repository. The test unregisters only its own repository and checks that
pre-existing repository settings remain unchanged:

```console
$ pwsh -NoLogo -NoProfile -File eng/Test.ps1 \
    -Suite Install \
    -PackageRoot artifacts/local-build
```

The `Install` and `All` suites select PSResourceGet 1.1.1 on the baseline
runtime and 1.2.0 on PowerShell 7.6 or later. Both are exact pins; the runner
does not download a missing version. Use `-PSResourceGetVersion` to select
either pin explicitly when verifying a different installed tool combination.

Execute the owned real-tmux fixture's lifecycle checks:

```console
$ pwsh -NoLogo -NoProfile -File eng/Test.ps1 -Suite Fixture
```

Execute the read cmdlets against installed artifacts and an owned tmux server:

```console
$ pwsh -NoLogo -NoProfile -File eng/Test.ps1 \
    -Suite Read \
    -PackageRoot artifacts/local-build
```

The `Capture`, `Create`, `Remove`, `Input`, `Formatting`, `Runtime`, `Help` and
`Examples` suites use the same artifact argument. `All` runs the implemented
suites; it does not imply the full architecture or compatibility matrix is
complete.
The runner removes ambient `TMUX` and `TMUX_PANE` only from test child
processes. `Create` verifies native creation plus first-daemon cleanup on
success and injected consumer failure in separate disposable processes.

Task-guide fences are checked against `examples/Guides.ps1`. Check source IDs,
registration and snippet drift without importing the product or starting tmux:

```console
$ pwsh -NoLogo -NoProfile -File tests/GuideExamples.Tests.ps1
```

Execute the guide operations from installed packages with native outcomes and
owned cleanup. The `Guides` suite is also included in `All`:

```console
$ pwsh -NoLogo -NoProfile -File eng/Test.ps1 \
    -Suite Guides \
    -PackageRoot artifacts/local-build
```

Install the pinned analyzer and help generator during setup:

```console
$ pwsh -NoLogo -NoProfile -File eng/Setup.ps1
```

Run PowerShell analysis after setup, without downloading tools:

```console
$ pwsh -NoLogo -NoProfile -File eng/Lint.ps1
```

Native help is authored under `docs/reference/` and generated with the pinned
PlatyPS version. Check that the packaged MAML matches its source:

```console
$ pwsh -NoLogo -NoProfile -File eng/Help.ps1 -Check
```

Omit `-Check` to regenerate help before building and packaging. Run the
generator in a fresh process: its authoring dependencies must not share the
product module's assembly load context.

Check C# formatting without rebuilding:

```console
$ dotnet format src/LibTmux.PowerShell/LibTmux.PowerShell.csproj \
    --verify-no-changes \
    --no-restore
```

```console
$ dotnet format src/LibTmux.Workspace.PowerShell/LibTmux.Workspace.PowerShell.csproj \
    --verify-no-changes \
    --no-restore
```

Build and packaging are outer-loop work. Package consumer checks cover
both import orders, module-qualified calls, native types, reimport, no-tmux
imports and assembly conflicts. Fixture checks are integration tests.
The complete platform, example and API suites are not established yet.

## Checks

For repository changes, review the complete diff, check relative Markdown
links and symlink targets, and confirm that ignore rules leave source and
shared configuration visible to Git.

Check unstaged changes for whitespace errors:

```console
$ git diff --check
```

Check staged changes before committing:

```console
$ git diff --cached --check
```

As executable checks are added, measure the whole command, including startup
and setup. Libraries should aim for the stretch budgets.

| Loop | Budget | Stretch | Scope |
| --- | --- | --- | --- |
| Inner | Under 5 seconds | Under 2 seconds | Tests for the changed code |
| Mid | Under 30 seconds | Under 10 seconds | Unit suites, lint, generated-file checks |
| Outer | Under 5 minutes | Under 60 seconds | Type checks, builds, integration suites, full matrices |

Run the inner loop after each edit, the mid loop after each change and before
handoff, and the outer loop before a code commit or pull request.

Keep network access, installs, production builds, browsers, sleeps, and broad
corpus scans out of the inner and mid loops. Treat a timeout or wait over one
second as a structural bug: investigate the cause and use events or
subscriptions instead of sleeps. Tag slow tests with a one-line reason and
put them in the outer loop. Fix an over-budget loop before adding tests; do
not raise its budget.

Benchmarks are separate: keep a run below ten minutes and a full sweep below
one hour. Reduce the workload when necessary.

## Testing tmux behavior

Verify tmux behavior against a real server. Use
focused unit tests for code that does not need tmux. Add regression tests for
verified defects, not tests that merely repeat implementation details.

Each test or probe must own an isolated socket and temporary directory with a
`libtmux-powershell-` prefix. Address that socket explicitly with `-S` or `-L`,
clear inherited `TMUX` and `TMUX_PANE` for child commands, and clean up only
the server and files created by that run, including on failure. Never use the
default tmux server or sweep another port's temporary files.

Record the actual tmux version when behavior depends on it. A passing subset
does not establish support for an entire version range.

## Pull requests

Keep one subject per pull request and one logical change per commit. Review
the complete diff, preserve unrelated work, and stage explicit paths.

Describe the concrete problem and resulting behavior. Report the commands
run, their elapsed times, and what passed, failed, or was skipped. Include
measured evidence for performance claims and migration guidance for
incompatible behavior. Follow [WRITING.md](WRITING.md) for commit messages.

Do not claim a package, supported platform, or public API until it exists and
has been verified. Publishing packages, releases, or tags requires a release
request; scaffold work does not establish a release process.

## Repository metadata

[repository.json](repository.json) records the description,
visibility, default branch, topics, and issue labels for both repositories:

- `origin`: [libtmux/libtmux-powershell](https://github.com/libtmux/libtmux-powershell).
- `tony`: [tony/libtmux-powershell](https://github.com/tony/libtmux-powershell).

Both are private, independent repositories with `master` as the default
branch. The personal repository is not a GitHub fork. Git does not apply the
metadata file automatically; apply settings through the GitHub CLI or API
and verify both repositories afterward.
