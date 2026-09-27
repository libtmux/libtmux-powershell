# Build a workspace from a file

Describe a session once, inspect the proposed tmux operations, and apply the
plan you reviewed. `LibTmux.Workspace` handles files and workspace commands;
`LibTmux` supplies native server, session, window and pane objects. Both use
[libtmux for .NET](https://github.com/libtmux/libtmux-dotnet)'s shared engine.

Install both modules as described in the [README](../README.md#install-from-source).
Choose an explicit `$server` with [New-TmuxServer](read.md).
The following workflow creates a detached `development` session with two
shell panes in your project directory. It needs tmux and `/bin/sh` on a Unix
host. The session remains available after the commands finish; remove it
when done using [Remove-TmuxSession](remove.md).

## Load and resolve the declaration

Save this declaration as `development.yaml`. Set `$workspacePath` to its
literal file path and `$projectRoot` to your project's absolute directory.

<!-- declaration: workspace.basic -->
```yaml
session_name: development
start_directory: ${PROJECT_ROOT}
options:
  default-command: exec /bin/sh
windows:
  - window_name: editor
    layout: even-horizontal
    options:
      automatic-rename: 'off'
    panes:
      - options:
          '@role': editor
      - focus: true
```

`Get-TmuxWorkspace` emits a `FileInfo`. Import parses the file; Resolve
returns a declaration with explicit directory expansion. Neither creates
sessions or executes commands.

<!-- example: workspace.01-load -->
```powershell
$workspace = Get-TmuxWorkspace -LiteralPath $workspacePath -ErrorAction Stop |
    Import-TmuxWorkspace -ErrorAction Stop |
    Resolve-TmuxWorkspace -BaseDirectory (Split-Path -LiteralPath $workspacePath) -Variables @{ PROJECT_ROOT = $projectRoot } -ErrorAction Stop
```

Only the supplied string variables participate in `$NAME` or `${NAME}`
expansion; the resolver does not copy the process environment. Supply `HOME`
explicitly when the declaration uses `~`. `$$` preserves a literal dollar
sign. Resolution applies to directories, not command text, names or options.
The base directory also records the origin for an allowed `before_script`.

For discovery, `Get-TmuxWorkspace` lists nearby `.tmuxp.yaml`, `.tmuxp.yml`
and `.tmuxp.json` files before the first configured global directory.
`-Name development` selects a global basename, while `-LiteralPath` chooses
one exact file. Use `-AllLocations` to include shadowed global locations.
`-Search editor` searches filenames; `-SearchIn Path` also searches parent
directories, while `-SearchIn Window` parses declared window names. Search
never executes declaration commands.
See the [discovery reference](reference/LibTmux.Workspace/Get-TmuxWorkspace.md)
for precedence, ambiguity and traversal limits.

## Validate before contacting tmux

Check declaration and policy constraints locally. Success emits `$true`.
With `-ErrorAction Stop`, an invalid declaration stops this workflow.

<!-- example: workspace.02-validate -->
```powershell
$workspace | Test-TmuxWorkspace -ErrorAction Stop
```

This does not verify directory existence, shell syntax, tmux option support
or session conflicts. Without `-ErrorAction Stop`, an invalid declaration
writes an error and then `$false`; later pipeline records can continue.

## Plan and review

Planning observes only the selected endpoint and freezes the actions and
policies. The default conflict policy refuses an existing session with the
same name. `CreateOrJoin` permits application to start an absent daemon or
join one that appeared since planning; it grants no ownership of the daemon.
Use `RequireExisting` when planning must find one already running.

<!-- example: workspace.03-plan -->
```powershell
$workspacePlan = $workspace | Get-TmuxWorkspacePlan -Server $server -ExistingSession Error -ServerStartup CreateOrJoin -ErrorAction Stop
```

Inspect the ordered actions before applying them. The default view shows each
action's symbolic target and source, plus a safe summary of its arguments:
layout, dimensions when set, option name, readiness timeout and host limits.
It marks scripts, pane text, option values, paths and environment without
printing their contents. Reading the plan performs no I/O.

<!-- example: workspace.04-review -->
```powershell
$workspacePlan.Actions
```

To inspect exact arguments in a trusted terminal, read an action's typed
`Request` property. It contains the script, command, option value and other
values that the default view hides. If planning used `-CompensateOnFailure`,
inspect `$workspacePlan.CompensationActions` separately; those actions run only
after a failed application. Targets are plan symbols bound to created tmux
identities during application.

The plan includes the transient bootstrap window used to install session
options before starting the described panes. It also includes the final
`CaptureResult` observation. tmux hooks can observe that bootstrap lifecycle.

Preview the endpoint, session, policies and effects through PowerShell's
confirmation mechanism. Preview emits no result and dispatches nothing.

<!-- example: workspace.05-preview -->
```powershell
$workspacePlan | Invoke-TmuxWorkspace -WhatIf
```

## Apply the reviewed plan

After review, apply that exact plan. Omitting `-Confirm:$false` retains the
high-impact confirmation prompt. Invocation does not reread the source file
or silently construct a replacement plan when its preconditions are stale.

<!-- example: workspace.06-apply -->
```powershell
$workspaceResult = $workspacePlan | Invoke-TmuxWorkspace -Confirm:$false -ErrorAction Stop
```

`$workspaceResult.Session` and `.Windows` are native objects from the final
captured graph. `.Journal` records action outcomes; `.Unsupported` lists
requested final layouts tmux rejected while leaving their windows usable.
The observation spans an interval, so concurrent changes can make it fail.

To load the workspace into your foreground terminal, run
`$workspaceResult.Session | LibTmux\Enter-TmuxSession -ErrorAction Stop`
after the successful application. Run it outside tmux with terminal stdin;
detach normally to receive one refreshed native session. The borrowed daemon
and workspace remain running after you detach. See
[Enter-TmuxSession](reference/LibTmux/Enter-TmuxSession.md) for its terminal
and cancellation contract.

`Enter-TmuxSession` accepts the native Session, not WorkspaceResult. It asks
for its own PowerShell confirmation when requested. `-WhatIf` on
`Invoke-TmuxWorkspace` emits no result to attach. A failed application with
`-ErrorAction Stop` emits no result for this step. Entering a session does not
undo workspace effects if the terminal client is cancelled or fails.

For an existing session, choose `Reuse`, `Append` or `Replace` explicitly
when planning. Reuse returns the inspected session without declaration
effects; Append adds windows while retaining existing session options;
Replace removes the inspected session before creating its replacement.
Review those actions before approving them.

## Export a starting declaration

Capture an existing session at pane depth before converting it. Set
`$exportPath` to the literal path for the YAML file you want to write. The
conversion reads the capture only; `Set-Content` writes the file.

<!-- example: workspace.07-export -->
```powershell
($server | Get-TmuxSnapshot -Depth Panes -ErrorAction Stop).Sessions |
    Select-TmuxSession -Criteria @{ Name = 'development' } -ExactlyOne -ErrorAction Stop |
    ConvertTo-TmuxWorkspace -ErrorAction Stop |
    ConvertTo-TmuxWorkspaceYaml -ErrorAction Stop |
    Set-Content -LiteralPath $exportPath -Encoding utf8NoBOM -ErrorAction Stop
```

Conversion warns because it omits observed options, environment, terminal
text, entity IDs, indices and shared-link identity. It cannot reconstruct the
original startup commands or shell intent. Repeated window links become
separate declarations. Check the exported layout and pane paths, add the
commands you want on a future load, then import, resolve and review a new plan.
For JSON, use `ConvertTo-TmuxWorkspaceJson` in place of the YAML converter.
See [ConvertTo-TmuxWorkspace](reference/LibTmux.Workspace/ConvertTo-TmuxWorkspace.md)
for the captured-field and literal-path rules.

## Edit the declaration

Choose a file and an installed editor explicitly. `$workspaceFile` is the
`FileInfo` returned by `Get-TmuxWorkspace`; `$editor` is an `ApplicationInfo`
returned by `Get-Command -Name nvim -CommandType Application -ErrorAction Stop`
(or your chosen editor). Set `[string[]] $editorArguments = @()` for no extra
arguments. A GUI editor that returns immediately needs its own wait option,
such as `@('--wait')` where the selected editor supports it.

Run this as a foreground command in your terminal, without assigning, piping
or redirecting its output. The file's absolute path is one argument. Arguments
are passed separately, including spaces, quotes and empty strings.

<!-- example: workspace.08-edit -->
```powershell
& {
    $ErrorActionPreference = 'Stop'
    $PSNativeCommandArgumentPassing = 'Standard'
    $PSNativeCommandUseErrorActionPreference = $false
    & $editor @editorArguments $workspaceFile.FullName
    if ($LASTEXITCODE -ne 0) {
        throw "Editor exited with code $LASTEXITCODE."
    }
}
```

A nonzero editor exit stops the block with the exit code. Launch errors also
stop it. Exit the editor normally when finished. Ctrl+C follows the editor's
and terminal's normal behavior; some editors treat it as an editing command
and stay open. This recipe has no `-WhatIf`, forced-stop or process-tree
cleanup contract. It does not undo edits already saved.

Editing runs no workspace command or tmux operation. Import, resolve, validate
and review a new plan explicitly afterward. An existing plan still contains
the declaration captured when it was created.

## Startup, host effects and failures

`-Readiness Immediate` sends configured commands as literal input followed
by Enter. It does not infer shell readiness or command completion. With
`-Readiness Cooperative`, pane startup receives a fresh
`LIBTMUX_WORKSPACE_READY` channel and must signal it when it can accept
input, using the selected tmux executable and the same server. The shell
operation is `tmux wait-for -S "$LIBTMUX_WORKSPACE_READY"`. A signal sent
before the wait is retained. `-ReadinessTimeout` bounds each wait in seconds;
completion of the sent command needs its own application signal. See the
[shared engine's cooperative startup example](https://github.com/libtmux/libtmux-dotnet/blob/master/src/LibTmux.Workspace/README.md#readiness-and-existing-sessions).

A declaration's `before_script` runs on the host only when planning admits
it with `-AllowHostScripts`. Resolve the document first; the script runs in
its recorded document directory. Supply the same policy to
`Test-TmuxWorkspace` and `Get-TmuxWorkspacePlan`, including
`-HostScriptTimeout` and `-MaxHostOutputBytes` when changing their bounds.
Invocation uses those frozen settings. Validation, planning and `-WhatIf`
never run the script. Review both host scripts and pane commands before
applying files from another source.

Application failures write `Tmux.WorkspaceApplyFailed` with a native
`WorkspaceBuildException`; they do not emit a partial success object. With
`-ErrorAction Stop`, a `catch` block can inspect `$_.Exception` through its
`.PartialResult`, `.Journal`, `.CompensationJournal`, `.Dispatch` and
`.InnerException` properties. With normal error handling, later plans can continue.
A stopped PowerShell pipeline may suppress error delivery, so do not rely
on receiving a journal after stopping it.

`-CompensateOnFailure` at planning requests bounded cleanup of creations
whose ownership is proven by that application. Review
`$workspacePlan.CompensationActions` too. `-CleanupTimeout` bounds cleanup;
it cannot undo shell or host side effects. The module never owns a borrowed
daemon and never guesses cleanup targets from names.

The declaration format covers session/window/pane options, layouts, focus,
environment, directory inheritance and command lists. Unsupported keys are
errors. For complete policy parameters, see
[Get-TmuxWorkspacePlan](reference/LibTmux.Workspace/Get-TmuxWorkspacePlan.md)
and [Invoke-TmuxWorkspace](reference/LibTmux.Workspace/Invoke-TmuxWorkspace.md).
