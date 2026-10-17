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

The target baseline is PowerShell 7.4 with .NET 8 on Linux. The
[macOS trial](workflows/macos-trial.yml) is advisory and does not establish
support. Keep module, folder, and manifest casing consistent. Export cmdlets
explicitly and do not export aliases that could shadow the `tmux` executable.
Pin the bundled LibTmux dependency to an exact version when a project is added.

Gallery releases use `0.1.0-alphaN`, starting at `0.1.0-alpha1` and
incrementing N for each release, until the maintainer explicitly chooses a
different release line or a stable release. This is independent of the
LibTmux NuGet version. Keep `ModuleVersion = '0.1.0'` and set
`PrivateData.PSData.Prerelease` to the release's `alphaN` suffix in both
manifests. Workspace's package dependency requires the exact core prerelease;
its runtime manifest uses numeric `RequiredVersion = '0.1.0'`. The first
release uses `alpha1` and requires `LibTmux` `0.1.0-alpha1`. Record the bundled
.NET dependency version in release notes.
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

Both modules consume published .NET alpha.20 packages, pinned in
[Directory.Packages.props](../Directory.Packages.props). Restore uses NuGet.org,
the optional `build/nuget` feed, and an isolated `build/packages` cache.
Restore checks the committed lockfiles and stages both modules:

```console
$ pwsh -NoLogo -NoProfile -File eng/Build.ps1 \
    -Restore
```

When changing a dependency, update its exact reference and run with
`-Restore -UpdateLock`. Shared .NET development can use the optional
[review-package workflow](#review-package-builds).

## Review package builds

Use this workflow to test shared .NET source changes before publication.
It needs Git, Python 3.9 or newer and the .NET SDKs required by
[BootstrapReview.ps1](../eng/BootstrapReview.ps1), in addition to the normal
setup. From a clean committed checkout, choose a new sibling output directory:

```console
$ pwsh -NoLogo -NoProfile -File eng/BootstrapReview.ps1 \
    -OutputDirectory "$PWD/../libtmux-powershell-review"
```

The bootstrap builds the .NET revision pinned in
[BootstrapReview.ps1](../eng/BootstrapReview.ps1) under a unique package version.
It writes inspected .NET archives to `feed/`, PowerShell archives to
`module-packages/`; `bootstrap.json` records package hashes and the status and
paths of the `Package` and `Install` check receipts. Use its printed paths for
further tests. It leaves this checkout's pins and lockfiles unchanged and
publishes nothing. If a run fails, keep its partial output for inspection and
retry with a new output directory after resolving the error.

To reuse those review archives, work in the bootstrap's disposable `port/`
checkout. Its pins and locks identify the exact inspected bytes. Set
`CORE_PACKAGES` to the corresponding `feed/` directory:

```console
$ pwsh -NoLogo -NoProfile -File eng/Build.ps1 \
    -Restore \
    -CorePackageDirectory "$CORE_PACKAGES" \
    -PackageCache build/review-package-cache
```

Choose a fresh cache directory for the first consumer proof.
`-CorePackageDirectory` requires `-Restore`: it checks the inspected
core/query/workspace hashes before restore and does not repack the archives.
Keep lock checking enabled when consuming the existing archives.

To build shared .NET source manually, use a new, unused prerelease identifier.
The archives contain ZIP entry timestamps, so rebuilding the source is not a
promise to reproduce the locked package bytes. Do not overwrite or recreate a
review version to satisfy existing locks.

Set `CORE_SOURCE` to a clean checkout of the shared source, `CORE_REVISION` to
its full Git revision, `REVIEW_VERSION` to the new identifier, and
`CORE_PACKAGES` to a new output directory. Use absolute directory paths.
The checkout uses its own SDK pin; avoid running this recipe while another
task builds in that checkout. Its
[review package recipe](https://github.com/libtmux/libtmux-dotnet/blob/v0.0.0-alpha.20/eng/package_review.py)
packs the shared packages, runs their native inspector and writes archive
hashes to `provenance.json`:

```console
$ python "$CORE_SOURCE/eng/package_review.py" \
    --version "$REVIEW_VERSION" \
    --revision "$CORE_REVISION" \
    --output "$CORE_PACKAGES"
```

Deliberately update the three exact LibTmux dependency pins in `Directory.Packages.props`
to `REVIEW_VERSION`, then regenerate the locks against these new archives:

```console
$ pwsh -NoLogo -NoProfile -File eng/Build.ps1 \
    -Restore \
    -UpdateLock \
    -CorePackageDirectory "$CORE_PACKAGES" \
    -PackageCache build/new-review-package-cache
```

Review the changed versions and content hashes in both lockfiles, then run
the installed package checks below. Subsequent restores omit `-UpdateLock`.
These commands create local review artifacts; they do not publish archives.

## Build and check modules

After restore, rebuild and stage without network access:

```console
$ pwsh -NoLogo -NoProfile -File eng/Build.ps1
```

Create local `.nupkg` module artifacts using PSResourceGet 1.1.1, included
with the baseline PowerShell installation. This does not publish them:

```console
$ PSModulePath="$PWD/build/Modules" \
    pwsh -NoLogo -NoProfile -File eng/Package.ps1 \
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

The `Snapshot`, `Capture`, `Create`, `Remove`, `Input`, `Wait`, `Options`,
`Hooks`, `Environment`, `Layout`, `Placement`, `Clients`, `Formatting`,
`Runtime`, `Help` and `Examples` suites use the same artifact argument. Run
`Product` and `Documentation` separately for the complete implemented checks
within the outer-loop budget. `All` combines those selections; none establishes
the full architecture or compatibility matrix.
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

For a full installed check, run the product and documentation selections in
separate processes:

```console
$ pwsh -NoLogo -NoProfile -File eng/Test.ps1 \
    -Suite Product \
    -PackageRoot artifacts/local-build
```

```console
$ pwsh -NoLogo -NoProfile -File eng/Test.ps1 \
    -Suite Documentation \
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

Check that code blocks in every Markdown page and the example programs stay
within 80 columns:

```console
$ python3 eng/check_example_width.py
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
$ dotnet format \
    src/LibTmux.Workspace.PowerShell/LibTmux.Workspace.PowerShell.csproj \
    --verify-no-changes \
    --no-restore
```

Build and packaging are outer-loop work. Package consumer checks cover
both import orders, module-qualified calls, native types, reimport, no-tmux
imports and assembly conflicts. Fixture checks are integration tests.
The complete platform, example and API suites are not established yet.

## Documentation API export

Run `eng/Setup.ps1` to install the pinned PlatyPS tool before exporting.
The exporter reads authored prose, links, defaults, and examples with PlatyPS
in a separate process, then combines them with packaged help and native
command metadata. Website exports retain inline code, Markdown links, and
keyboard-key markup. Packaged MAML uses plain prose for `Get-Help` and keeps
its related links; it does not change the displayed executable examples.

Export the public command surface from a committed source checkout:

```console
$ pwsh -NoLogo -NoProfile -File eng/Export-Docs.ps1 \
    -Restore
```

The exporter rebuilds both modules and writes `build/docs/api.json`. It
compares the manifest exports with native command discovery and packaged
MAML help. Each command retains its parameter sets, pipeline binding,
validation, confirmation behavior, input/output types, examples and source
locations. Roslyn reads declarations and initializers without executing
them. The artifact records the source revision, input hashes and tool
versions; changed API or help sources fail extraction.

Omit `-Restore` after the locked dependencies have been restored. Use
`-SourceRoot` to extract another committed checkout with this exporter,
and `-OutputPath` to select another artifact destination. The exporter hash
identifies the tooling independently of the selected API source.
Run the contract check:

```console
$ pwsh -NoLogo -NoProfile -File tests/DocsExport.Tests.ps1
```

This checks extraction fidelity, including a missing-parameter-set negative
control. It does not execute the documented examples or establish that the
website has rendered or published the artifact.

The Linux build job runs the exporter and contract check after native help
validation. It saves `powershell-docs-api` as a separate CI artifact before
packing the modules. Website previews and publication use the shared
documentation workflow and retain their own source and tooling provenance.

## Website publication

The [docs workflow](workflows/docs.yml) builds the selected source with the
shared libtmux.org workflow. Keep its build and publisher references pinned
to the same full commit in `libtmux/docs`. The native exporter comes from the
calling workflow's tested commit; its provenance stays separate from the
selected source revision.

A `master` push publishes `/en/powershell/latest/`. A `v*` release tag
publishes its version plus `next` for prereleases or `stable` for releases.
Same-repository pull requests publish `/en/powershell/pr-N/` from the tested
merge commit. Before publishing, the workflow checks that the PR is still
open in this repository and its current head and merge match the tested
revision. Fork pull requests build without publishing. Closing a pull
request deletes only its preview prefix, after confirming it is still
closed. Cleanup shares the build and publication queue; rerunning an old
closed event cannot delete a reopened PR's preview.

To rebuild an existing revision, dispatch `docs.yml` from `master`. Set
`source-ref`, `version`, `version-kind`, `is-default`, `resolves-to`, and
`publish`. Use `resolves-to` only for an alias. Leave `publish` false for a
build-only check. An immutable version must still identify its original
source and package version. Inspect the build provenance and hosted page
after publishing; a successful native export alone is not publication proof.

## Gallery releases

The [release workflow](workflows/release.yml) publishes the two module
archives already tested by Linux CI. It does not build or repackage them.
Use the successful `powershell` push run for the current `master` commit;
pull request runs are rejected. The workflow validates that the run and
archives belong to the selected source commit.

Set `CI_RUN_ID` to that run's numeric ID. Validate its archives without
uploading:

```console
$ gh workflow run release.yml \
    --repo libtmux/libtmux-powershell \
    --ref master \
    --field ci_run_id="$CI_RUN_ID" \
    --field publish=false
```

After a publishing-workflow repair, set `release_tag` to the existing
annotated `v0.1.0-alphaN` tag and use that source commit's successful CI run.
The tag must point to an ancestor of the workflow's `master` commit. This
uses the repaired publishing code with the original tested archives; it
does not rebuild packages or move the release tag. For example, validate
the alpha2 archives:

```console
$ gh workflow run release.yml \
    --repo libtmux/libtmux-powershell \
    --ref master \
    --field ci_run_id="$CI_RUN_ID" \
    --field release_tag=v0.1.0-alpha2 \
    --field publish=false
```

After reviewing the successful validation, use the same command with
`publish=true` to publish. This uploads `LibTmux` first, verifies its public
package, then uploads `LibTmux.Workspace`. The workflow uses the repository
Actions secret `PSGALLERY_API_KEY` only in that step. macOS is advisory;
the build, four Linux endpoint combinations and aggregate gate must pass.

Publication is separate for each module. A failed second upload leaves
the first module published. Rerun the same release only after checking
the receipt: existing packages must match the tested payload, and only
missing packages are uploaded. A differing payload under the same version
is rejected. Release artifacts retain the source, CI run and package hashes.

The publisher's local entrypoint is `eng/Publish.ps1`; omitting `-Publish`
validates an artifact directory without network access or credentials.
After publication, `tests/ResourceInstall.Tests.ps1 -Gallery` verifies
Workspace-only installation from PSGallery and executes installed examples.

## MCP discovery

The [MCP guide](../docs/mcp.md) uses the separate `LibTmux.Mcp` .NET tool.
Its discovery suite is opt-in and is not part of `All`; it needs no PowerShell
module package. Install the published alpha.20 tool in a fresh directory:

```console
$ dotnet tool install LibTmux.Mcp \
    --tool-path build/mcp \
    --version 0.0.0-alpha.20 \
    --framework net8.0
```

For shared source changes, set `CORE_PACKAGES` to `packageFeed` and
`MCP_VERSION` to `version` from the review bootstrap's `bootstrap.json`.
Use a separate tool directory and add `--add-source "$CORE_PACKAGES"` to the
installation command, replacing its version with `"$MCP_VERSION"`.

The test client pins the official `ModelContextProtocol` SDK in its own
project and lockfile. Restore it during setup:

```console
$ dotnet restore tests/support/McpDiscovery/McpDiscovery.csproj \
    --locked-mode
```

Build the client before running the suite:

```console
$ dotnet build tests/support/McpDiscovery/McpDiscovery.csproj \
    --configuration Release \
    --no-restore
```

Set `MCP_COMMAND` to the installed tool's absolute path and `MCP_VERSION` to
its exact version, then run the
[client workflow](../docs/mcp.md#check-the-client-workflow-from-this-checkout).
The runner requires the existing executable and built probe; it does not
install, restore or build. It starts only its own tmux fixture and stdio
client. Tool installation and client compilation are setup/outer-loop work.

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

The complete installed `Product` suite has a 70-second outer budget.
`Documentation` keeps its 60-second budget. Individual test processes keep
their existing deadlines.

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

The supported matrix starts at tmux 3.3a. The version check suite also runs on
releases below it, where it asserts refusal with no effects. Run it against
the tmux first on `PATH`:

```console
$ pwsh -NoLogo -NoProfile -File eng/Test.ps1 \
    -Suite VersionCheck \
    -PackageRoot "$PACKAGE_ROOT"
```

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

The organization repository is public; the personal repository is private.
Both use `master` as the default branch and are independent repositories.
The personal repository is not a GitHub fork. Git does not apply the metadata
file automatically; apply settings through the GitHub CLI or API and verify
both repositories afterward.
