# Contributing

This repository is the scaffold for libtmux for PowerShell. It contains
repository configuration and contribution guides. There is no cmdlet
implementation, module manifest, package, test suite, or release workflow yet.

Read [AGENTS.md](AGENTS.md) for change discipline and [WRITING.md](WRITING.md)
for prose and commit conventions.

## Planned module

The module will expose C# cmdlets built on the LibTmux NuGet package from
[libtmux for .NET](https://github.com/libtmux/libtmux-dotnet). Use these names
when implementation begins:

| Surface | Name |
| --- | --- |
| Prose and documentation titles | libtmux for PowerShell |
| Gallery module and published folder | `LibTmux` |
| Manifest | `LibTmux.psd1` |
| Cmdlet project, assembly, and namespace | `LibTmux.PowerShell` |
| Cmdlet nouns | Singular `Tmux` nouns, such as `Get-TmuxSession` |
| Output types | LibTmux's own types, such as `LibTmux.Session` |
| Default views | `LibTmux.Format.ps1xml` |

The planned baseline is PowerShell 7.4 with .NET 8 on Linux and macOS. Keep
module, folder, and manifest casing consistent. Export cmdlets explicitly and
do not export aliases that could shadow the `tmux` executable. Pin the bundled
LibTmux dependency to an exact version when a project is added.

Module versions will use plain three-part `0.x` versions without prerelease
labels, independently of the LibTmux NuGet version. Describe the module as
alpha in prose and record the bundled dependency version in release notes.
These are naming and packaging decisions, not available package contents.

## Setup

[.tool-versions](.tool-versions) pins PowerShell and the .NET SDK for the
planned PowerShell 7.4 and .NET 8 baseline. Development pins do not establish
tested platform or tmux compatibility.

Install the pinned tools with mise:

```console
$ mise install
```

No dependency installation, build, or test command exists yet. Document those
commands here when the corresponding tooling is added.

## Checks

For scaffold changes, review the complete diff, check relative Markdown
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

When implementation begins, verify tmux behavior against a real server. Use
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

[.github/repository.json](.github/repository.json) records the description,
visibility, default branch, topics, and issue labels for both repositories:

- `origin`: [libtmux/libtmux-powershell](https://github.com/libtmux/libtmux-powershell).
- `tony`: [tony/libtmux-powershell](https://github.com/tony/libtmux-powershell).

Both are private, independent repositories with `master` as the default
branch. The personal repository is not a GitHub fork. Git does not apply the
metadata file automatically; apply settings through the GitHub CLI or API
and verify both repositories afterward.
