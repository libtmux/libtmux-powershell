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

## POSIX `sh` programs in tests

A test may write a minimal POSIX `sh` program in two places. A PowerShell
program starts too slowly for either, and the suites bound a wait at one second.

- **A stand-in for tmux.** It records or rewrites the arguments of a call and
  then runs the real tmux with `exec`, or answers a daemon start with a fixed
  result. A suite hands it to the library as the tmux binary, so the library
  starts it once for each tmux process it runs. A stand-in that runs on every
  tmux call, with no per-call logic, is a compiled program instead:
  `tests/support/RecordingTmux`.
- **A pane program.** A few lines that a test starts in a pane: print a marker,
  signal readiness with `tmux wait-for -S`, read input, then `exec /bin/cat`.
  The test waits for the signal with `Invoke-OwnedTmux`, which gives up after
  one second.

`rg -l '#!/bin/sh' tests` lists the files that write one.

### Start cost

The figures are `hyperfine` means of 20 runs after 3 warm-up runs, on a 12-core
WSL2 host with a tmux server running for the `wait-for` rows.

```console
$ hyperfine \
    -N \
    --warmup 3 \
    --runs 20 \
    ./empty.sh \
    ./empty.ps1 \
    ./signal.sh \
    ./signal.ps1
```

```console
$ hyperfine \
    -N \
    --warmup 3 \
    --runs 20 \
    'bash -c "./empty.sh & ./empty.sh & ./empty.sh & ./empty.sh & wait"' \
    'bash -c "./empty.ps1 & ./empty.ps1 & ./empty.ps1 & ./empty.ps1 & wait"'
```

| Program | `sh` | PowerShell |
| --- | --- | --- |
| Empty body | 0.5 ms | 181 ms |
| Signals `wait-for -S` | 1.8 ms | 194 ms |
| Empty body, four starting at once | 2.7 ms | 301 ms |

`empty.sh` is `exit 0` under `#!/bin/sh` and `empty.ps1` is `exit 0` under a
`pwsh -NoProfile` shebang. `signal.sh` and `signal.ps1` run
`tmux -S <socket> wait-for -S ready` in each language.

A PowerShell start takes a fifth of the one-second bound with nothing else
running, and the Product suites run three scripts at once. The bound leaves no
room for the second start a stand-in costs on every tmux call, and little for a
pane program, which is why neither is rewritten. No suite run with PowerShell
variants is claimed here.
