# Ordinary examples

The [quick start](../examples/QuickStart.ps1) imports `LibTmux`, starts or reuses the normal endpoint, and finds or creates a named workspace. You can copy its [README block](../README.md#start-or-reuse-a-workspace) into PowerShell without a fixture or socket argument. The server and session remain available when it finishes.

## Server availability

`Start-TmuxServer` returns a native `LibTmux.Server`. With no argument, it captures the normal endpoint defaults. Pipe a handle from `New-TmuxServer` to select explicit connection options. `New-TmuxServer` still constructs a handle without contacting tmux; `Connect-TmuxServer` still requires a running daemon.

For a missing daemon, startup reads the selected tmux configuration, creates a temporary session, sets the server's `exit-empty` option to `off`, and removes that session. The daemon remains usable without a bootstrap session. Resources created by your tmux configuration remain. Reusing a daemon preserves its sessions, windows, panes and existing configuration.

A successful startup needs no disposal scope. After the shared core returns its acquisition result, `Start-TmuxServer` retains that result until output handoff completes. If cancellation or downstream output prevents handoff, the cmdlet attempts cleanup only for a daemon started by that call. `Get-TmuxScopeFailure -Pending` retains a failed handoff cleanup and its retry owner. Reusing a server grants no destruction authority.

If startup or child creation fails before returning a result and rollback also fails, `Get-TmuxScopeFailure -Pending` retains each owner accepted by the shared core. Inspect its `BodyFailure` and `CleanupFailure`, then pass its `Owner` to `Close-TmuxScope` to retry. A lost receipt that never established ownership supplies no retry authority. The external example supervisor handles those unknown effects within its private test endpoint.

The quick start uses exact session and window names. It reuses `libtmux-demo` and `logs` when present; it does not replace their contents. The shared core adds its reserved `@libtmux_owner_generation` server option when creating owned resources. It preserves a valid existing token. An invalid token causes ownership-dependent operations to fail; startup's borrowed reuse leaves the token untouched.

## Endpoint defaults

The normal lookup order is an explicit socket path or name captured by `New-TmuxServer`, nonempty `LIBTMUX_SOCKET_PATH`, nonempty `LIBTMUX_SOCKET_NAME`, selected `TMUX` context, then tmux's named default. `TMUX_TMPDIR` controls the named socket directory. Handles capture their effective environment and executable path; later host changes do not redirect them.

The external test supervisor sets `LIBTMUX_SOCKET_PATH` or `LIBTMUX_SOCKET_NAME` in each example child. The source contains no test configuration. Its parent retains its environment. Each invocation has an independent endpoint and a supervisor that observes accepted process exit before removing its own directory.

## Test the displayed source

The ordinary-example runner compares the complete README block with `examples/QuickStart.ps1` before executing that file. It executes the same file twice to check name reuse and compares the returned native objects with tmux's live graph. The tests also check that existing user sessions, windows, panes, process identity and option values survive.

Set `EXAMPLE_RUNNER` to the shared documentation project's `scripts/example_environment.py`, `MODULES` to extracted module archives, and `TMUX` to the tmux binary to test. Run from this checkout:

```console
$ python3 tests/support/run_ordinary_examples.py \
    --runner "$EXAMPLE_RUNNER" \
    --pwsh pwsh \
    --module-root "$MODULES" \
    --tmux "$TMUX" \
    --output build/ordinary-examples
```

The output directory must be new. Repeat `--tmux` with each installed version to run the unchanged example under both socket selectors and both initial conditions. The `absent` condition starts no fixture daemon; the public startup call must make the endpoint usable. The `running` condition starts an isolated daemon and creates user-like state before executing the example. The harness suppresses personal tmux configuration through its command proxy, outside the example source.

`--checks examples` selects the source and version matrix. `--checks api` selects startup and handoff behavior, including cancellation and failed cleanup retry. `--checks faults` selects body failure, timeout, controller interruption, controller termination and concurrent runs. The default runs all three selections. These are Linux outer integration checks; the shared supervisor requires Linux pidfd support. The module retains its PowerShell 7.4 and .NET 8 floor.

Keep each run's `commands.json`, `summary.json`, worker observations, command trace and supervisor receipts. A failed body is not a passing example; the fault tests pass only when they observe the expected failure and verify cleanup. Never infer exit from a missing socket or delete a directory whose cleanup receipt reports an error.

## Continuing CI checks

The `OrdinaryExamples` suite in `eng/Test.ps1` runs the copied program and startup/handoff checks against absent and running daemons with both default socket selectors. It also runs focused startup, session readback, cancellation, aggregate-error and action-stop recovery cases. Each CI matrix lane uses the same inspected PowerShell archives as Product and Documentation and a revision-pinned shared supervisor.

The gate requires native execution and cleanup receipts for all 18 invocations. It rejects empty summaries, skipped assertions, changed installed bytes and missing exit observations. Its three groups run concurrently within a separate 60-second budget. [Contributor instructions](../.github/CONTRIBUTING.md#build-and-check-modules) show the command and explain the retained receipts. The longer fault sweep and the remaining recovery cases stay available through their dedicated runners.

## Cleanup demonstrations

[SessionCleanup.ps1](../examples/SessionCleanup.ps1) preserves the original create, capture and manual-cleanup program. [Lifecycle.ps1](../examples/Lifecycle.ps1) demonstrates `Invoke-TmuxScope`. Their destruction assertions belong to those examples; the ordinary quick start leaves its workspace for its caller. The test supervisor owns final cleanup in both cases.

Markdown source equality and native PowerShell MAML help have port-specific checks. Astro Markdown/MDX, Sphinx reStructuredText/MyST and Python doctest remain in the shared adapter scope; this runner does not implement those adapters.
