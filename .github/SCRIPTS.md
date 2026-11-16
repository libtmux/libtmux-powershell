# Scripts

This policy covers the support scripts in this repository: files under
`scripts/`, CI helpers, generators and checkers. It applies the libtmux
decision in [libtmux/docs#323](https://github.com/libtmux/docs/pull/323).

## Keep a script only for a current use

A script stays when this project runs it today: a CI job, a release step, a
code generator, a documentation check, or a maintainer task named in
[CONTRIBUTING.md](CONTRIBUTING.md).

- Parity with Python libtmux or tmuxp is not a use. Delete comparison
  harnesses, oracles, ledgers and generated fixtures, and the CI steps that
  install them.
- A shell step that creates, prepares or stops tmux for an example or test
  means the library lacks an operation. File an issue for the operation and
  remove the step when it lands.
- Delete scripts nothing calls.
- Tooling several ports share lives once, as a shared workflow or action, not
  as a vendored copy.

## Language

Scripts are PowerShell, run with `pwsh -File`, the same interpreter CI uses
for the library. Do not add shell or Python script files.

## Layout and checks

- A script with tests lives in `scripts/<name>/`, with a `README.md` (what it
  does, who runs it, how) and `tests/`. A short single-purpose script may be
  one file with a usage header.
- Scripts pass the same formatter, linter, type checker and test runner as the
  library, in CI.
- Use current language and tool idioms; no shims below the project's floor.
- Before a new or rewritten script merges, a reviewer who did not write it
  checks it against [WRITING.md](WRITING.md) and
  [no-ai-slop](https://github.com/petergyang/no-ai-slop).

## What stays

- GitHub Actions `run:` lines that call one command.
- A capability PowerShell lacks comes from a test-only PowerShell dependency,
  not from a second language.
- Test data that is not a comparison, such as workspace files a loader reads.
- A minimal POSIX `sh` script that stands in for tmux in a test. It records or
  rewrites the arguments of a call and then runs the real tmux with `exec`, or
  answers a daemon start with a fixed result. A suite hands it to the library
  as the tmux binary, so the library starts it once for each tmux process it
  runs. A PowerShell script is not a substitute:
  - It starts slowly. A script with an empty body behind a `pwsh` shebang takes
    about 250 ms to start, and about 380 ms with four starting at once on four
    cores. The `sh` script takes 1 ms. The measurement ran on a 12-core WSL2
    host under load, with the first command below.
  - It breaks the suites' one-second bounds. `Invoke-OwnedTmux` waits one
    second by default, and `tests/Wait.Tests.ps1` asserts that a stopped wait
    ends within one second. With an equivalent PowerShell stand-in the Wait
    suite passed 1 of 5 runs, every failure a timeout; with the `sh` stand-in
    it passed 5 of 5.
  - It costs a start for every call. The Layout suite runs its stand-in 9
    times, and took 5.0 s with `sh` and 6.4 s with PowerShell.
  - It cannot `exec`. The process the library signals is `pwsh`, and the tmux
    client is its child, but the Wait suite reads the client's process ID from
    the stand-in and asserts that the client exits.

  ```console
  $ hyperfine \
      -N \
      --warmup 3 \
      --runs 20 \
      ./shim.sh \
      ./shim.ps1
  ```

  `shim.sh` is `exec /usr/bin/true "$@"` under `#!/bin/sh`; `shim.ps1` is
  `exit 0` under a `pwsh` shebang. The suite figures come from running each
  suite against the modules that `eng/Build.ps1 -Restore` stages, once as
  written and once with its stand-in rewritten in PowerShell:

  ```console
  $ pwsh -NoLogo -NoProfile -File tests/Wait.Tests.ps1 -ModuleRoot build/Modules
  ```

  These suites, each `tests/<name>.Tests.ps1`, write the stand-in: Attachment,
  Capture, Completion, Create, CreateStartup, Criteria, Features, Fixture,
  Formatting, GuideExamples, Input, Layout, Placement, Remove, Rename,
  Sandbox, Selectors, Snapshot, SourceQuery, VersionCheck, Wait,
  WorkspaceApply and WorkspaceSerialization. A stand-in that runs on every tmux
  call, with no per-call logic, is a compiled program instead:
  `tests/support/RecordingTmux`.
