# Standalone core pane enumeration benchmark

This benchmark captures a pane-depth snapshot through a standalone .NET 8
process. Its owned tmux fixture matches the pane enumeration benchmark: one
session, four windows, and sixteen panes. Native `list-panes` supplies the
expected pane IDs. The runner requires every C# capture to return those same
sixteen IDs and checks that a deliberately wrong reference is rejected.

The build consumes `LibTmux.dll` and its dependency closure embedded in the
Product-tested `LibTmux.0.1.0-alpha2.nupkg`. Preparation verifies the exact assembly
hashes and identities in `dependencies.json`, restores a project with no
package references from an empty local feed, then builds with `--no-restore`.
It writes output only under a new preparation directory. This proves an
embedded exact-library baseline; it does not test clean NuGet dependency
resolution or use a .NET source project reference.

Both commands read the embedded core version from the package and verify its
assembly closure. Pass the same clean-bootstrap `-ReviewRoot` to both commands
to verify package bytes against the inspected .NET feed and reviewed PowerShell
build. Without that receipt, reports mark source provenance `unverified`.

Create the module archive as described in the
[contributor guide](../../.github/CONTRIBUTING.md#setup), then prepare the
standalone executable:

```console
$ pwsh -NoLogo -NoProfile -File benchmarks/StandaloneCore/Prepare.ps1 \
    -PackageRoot artifacts/local-build \
    -OutputRoot artifacts/benchmarks/standalone-core-prepared
```

Run three warmup and twenty sample rounds against an owned socket:

```console
$ pwsh -NoLogo -NoProfile -File benchmarks/StandaloneCore/Run.ps1 \
    -PackageRoot artifacts/local-build \
    -PreparedRoot artifacts/benchmarks/standalone-core-prepared \
    -OutputPath artifacts/benchmarks/standalone-core.json
```

Both commands refuse existing output paths. `-TmuxBinaryPath` selects the
executable to measure. Preparation uses an explicit offline restore; the
runner only checks and executes the prepared binary. Neither command
publishes a package or starts the default tmux server.
The runner consumes each C# output record as it arrives and cancels the whole
run after nine minutes.

Each cold sample launches a new `dotnet` process and records wall time from
launch through exit, including runtime startup, assembly loading, first
snapshot, JSON output, and shutdown. It also records the first snapshot time
inside that process. A separate reused C# process records its first call,
warmups, and timed snapshot calls. The phases run serially, cold before warm.
They have different cost scopes, so the report does not calculate a speed
ratio between them.

The JSON report retains every elapsed time and returned pane ID set, plus
medians and p95 when a metric has at least twenty samples. It records the
module archive hash, verified assembly hashes, loaded assembly MVIDs, source
hashes, SDK and runtime versions, tmux version and hash, checkout state, and
owned-fixture cleanup. The capture samples exclude fixture setup. Keep raw
distributions and repeat clean runs before making a performance claim.
