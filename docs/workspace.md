# Build a workspace from a file

Describe a session once, review the proposed tmux operations, and apply the plan
you reviewed. `LibTmux.Workspace` handles files and workspace commands, and
`LibTmux` supplies the server, session, window and pane objects. Both use
[libtmux for .NET](https://github.com/libtmux/libtmux-dotnet)'s shared engine.

[Install LibTmux.Workspace](../README.md#build-a-workspace-from-a-file); it
installs the matching core module. Choose a `$server` with
[New-TmuxServer](read.md).

The workflow below creates a detached `development` session with two shell panes
in your project directory. It needs tmux and `/bin/sh`. The session stays after
the commands finish; remove it with [Remove-TmuxSession](remove.md).

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

`Get-TmuxWorkspace` emits a `FileInfo`, Import parses the file, and Resolve
returns the declaration with directories expanded. None creates a session or
runs a command.

<!-- example: workspace.01-load -->
```powershell
$resolve = @{
    BaseDirectory = Split-Path -LiteralPath $workspacePath
    Variables = @{ PROJECT_ROOT = $projectRoot }
}
$workspace = Get-TmuxWorkspace -LiteralPath $workspacePath -ErrorAction Stop |
    Import-TmuxWorkspace -ErrorAction Stop |
    Resolve-TmuxWorkspace @resolve -ErrorAction Stop
```

### Variables

- Only the string variables you supply expand, as `$NAME` or `${NAME}`. The
  resolver does not copy the process environment, so supply `HOME` if the
  declaration uses `~`. `$$` is a literal dollar sign.
- Resolution expands inherited directories and session, window and pane option
  values, including global and post-construction options.
- Unknown variables in option values stay literal; unresolved directory
  variables are errors.
- Option names, commands, the host script, session and window names, and
  environment values stay literal.
- The base directory also records the origin of an allowed `before_script`.

### Commands

- Ordered `shell_command` and `shell_command_before` lists take command strings
  and tmuxp-style entries such as `- cmd: exec /bin/sh`. Commands stay literal
  and run in session-before, window-before, pane-before, then pane order. The
  [workspace corpus](../tests/fixtures/workspace/corpus.yaml) has the mixed
  forms.
- `enter: false` on a pane or command types its text without submitting it. A
  command inherits the current Enter setting until another overrides it, and
  the default is `true`. The
  [pinned tmuxp fixtures](../tests/fixtures/workspace/tmuxp-v1.74.0-skip-send.yaml)
  cover pending text and execution after an explicit Enter.

### Window indices

`window_index` requests a nonnegative, session-relative index; without it tmux
picks the next free one. Duplicate requested indices fail validation, and an
index an existing window occupies fails when the reviewed plan is applied. The
[pinned tmuxp fixture](../tests/fixtures/workspace/tmuxp-v1.74.0-window_index.yaml)
has a sparse `0, 5, 1` session.

### `PATH`

tmux treats `PATH` specially. An unattached client can replace a pane's declared
`PATH` with its own during pane creation, while the session environment keeps the
declared value. Set `PATH` inside the pane shell when pane commands depend on it.

### Discovery

`Get-TmuxWorkspace` lists nearby `.tmuxp.yaml`, `.tmuxp.yml` and `.tmuxp.json`
files before the first configured global directory.

- `-Name development` selects a global basename, and `-LiteralPath` one exact
  file.
- `-AllLocations` includes shadowed global locations.
- `-Search editor` searches filenames. `-SearchIn Path` also searches parent
  directories, and `-SearchIn Window` parses declared window names. Search never
  runs declaration commands.

The [discovery reference](reference/LibTmux.Workspace/Get-TmuxWorkspace.md)
covers precedence, ambiguity and traversal limits.

## Choose when options apply

- **Window `options`:** take effect before startup input, extra panes and the
  final layout. Put options such as `main-pane-height` here so the layout uses
  them.
- **Window `options_after`:** apply after the startup commands are sent and the
  final layout is selected, so each pane gets its setup text before
  `synchronize-panes` broadcasts later input. They do not wait for those commands
  to finish.
- **Root `options`:** affect this session.
- **Root `global_options`:** change the server's global session defaults before
  the declared windows start. They can affect inherited settings in existing
  sessions and survive creation cleanup after a later failure, so review their
  scope before applying.

This declaration picks a shell for new windows, sizes the main pane and defers
synchronized input. The example returns a plan and changes nothing; review its
actions, then apply it with the workflow below.

<!-- example: workspace.11-options -->
```powershell
& {
    $declaration = Import-TmuxWorkspace -Yaml @'
session_name: option-staging
global_options:
  default-shell: /bin/sh
windows:
  - window_name: workers
    layout: main-horizontal
    options:
      main-pane-height: '5'
    options_after:
      synchronize-panes: 'on'
    panes:
      - shell_command: printf first
      - shell_command: printf second
'@
    $declaration | Get-TmuxWorkspacePlan -Server $server
}
```

The option actions keep native `SetOptionRequest` values. Their default view
shows `scope=Session global=True` for the global setting and hides option
values, and `scope=Owner` follows the action's session, window or pane target.
The confirmation preview also names global effects.

## Validate before contacting tmux

Check declaration and policy constraints locally. Success emits `$true`, and
`-ErrorAction Stop` makes an invalid declaration stop the workflow.

<!-- example: workspace.02-validate -->
```powershell
$workspace | Test-TmuxWorkspace -ErrorAction Stop
```

It does not check that directories exist, shell syntax, tmux option support or
session conflicts. Without `-ErrorAction Stop`, an invalid declaration writes an
error and then `$false`, and later pipeline records continue.

## Plan and review

Planning reads only the selected endpoint and freezes the actions and policies.

- The default conflict policy refuses an existing session with the same name.
- [`CreateOrJoin`][workspaceserverstartup-createorjoin] lets application start an
  absent daemon or join one that appeared since planning. It grants no daemon
  ownership.
- [`RequireExisting`][workspaceserverstartup-requireexisting] makes planning
  require a daemon that is already running.

<!-- example: workspace.03-plan -->
```powershell
$planOptions = @{
    Server = $server
    ExistingSession = 'Error'
    ServerStartup = 'CreateOrJoin'
    ErrorAction = 'Stop'
}
$workspacePlan = $workspace | Get-TmuxWorkspacePlan @planOptions
```

A JSON window layout needs tmux 3.8. On an older server `Get-TmuxWorkspacePlan`
fails with a `WorkspaceFormatException` whose inner exception is the
`layout-json` refusal. Planning may probe the version but sends no layout or
creation command.

Review the ordered actions before applying them. The default view shows each
action's symbolic target and source and a safe summary of its arguments: layout,
dimensions when set, option name, readiness timeout and host limits. It marks
scripts, pane text, option values, paths and environment without printing them.
Reading the plan does no I/O.

<!-- example: workspace.04-review -->
```powershell
$workspacePlan.Actions
```

- To read exact arguments in a trusted terminal, use an action's typed
  [`Request`][workspaceaction-request] property. It holds the script, command,
  option value and other values the default view hides.
- If planning used `-CompensateOnFailure`, check
  [`$workspacePlan.CompensationActions`][workspaceplan-compensationactions]
  separately; they run only after a failed application.
- Targets are plan symbols that become created tmux identities during
  application.
- The plan includes the temporary bootstrap window that installs session options
  before the described panes start, and the final
  [`CaptureResult`][workspaceactionkind-captureresult] observation. tmux hooks
  can see the bootstrap's lifecycle.

`-WhatIf` previews the endpoint, session, policies and ordered actions through
PowerShell's confirmation. Each action and conditional cleanup step shows its
kind and symbolic target, and option actions add scope and global effects.
Request values stay hidden. A preview emits no result and sends nothing.

<!-- example: workspace.05-preview -->
```powershell
$workspacePlan | Invoke-TmuxWorkspace -WhatIf
```

## Apply the reviewed plan

After review, apply that exact plan. Without `-Confirm:$false` the high-impact
confirmation prompt stays. Invocation never rereads the source file or quietly
builds a replacement plan when its preconditions are stale.

<!-- example: workspace.06-apply -->
```powershell
$workspaceResult = $workspacePlan |
    Invoke-TmuxWorkspace -Confirm:$false -ErrorAction Stop
```

- [`$workspaceResult.Session`][workspaceresult-session] and `.Windows` are
  native objects from the final captured graph.
- `.Journal` records action outcomes.
- `.Unsupported` lists final layouts tmux rejected, whose windows stay usable.
- The observation spans an interval, so a concurrent change can make it fail.

To load the workspace into your terminal after a successful application, run
`$workspaceResult.Session | LibTmux\Enter-TmuxSession -ErrorAction Stop` outside
tmux, with terminal stdin. Detach normally to receive one refreshed session; the
borrowed daemon and workspace keep running. See
[Enter-TmuxSession](reference/LibTmux/Enter-TmuxSession.md) for the terminal and
cancellation rules.

- `Enter-TmuxSession` takes the `Session`, not the `WorkspaceResult`, and asks
  for its own confirmation when requested.
- `-WhatIf` on `Invoke-TmuxWorkspace` emits no result to attach, and a failed
  application under `-ErrorAction Stop` emits none either.
- Entering a session does not undo workspace effects if the terminal client is
  cancelled or fails.

For an existing session, choose
[`Reuse`][workspaceexistingsession-reuse],
[`Append`][workspaceexistingsession-append] or
[`Replace`][workspaceexistingsession-replace] when planning, and review those
actions before approving them:

- **Reuse:** returns the inspected session with no declaration effects.
- **Append:** adds windows, keeps local session options and applies declared
  global defaults.
- **Replace:** removes the inspected session before creating its replacement.

## Export a starting declaration

Capture an existing session at pane depth, then convert it. Set `$exportPath` to
the literal path of the YAML file to write. The conversion reads the capture
only; `Set-Content` writes the file.

<!-- example: workspace.07-export -->
```powershell
($server | Get-TmuxSnapshot -Depth Panes -ErrorAction Stop).Sessions |
    Select-TmuxSession -ExactlyOne -ErrorAction Stop -Criteria @{
        Name = 'development'
    } |
    ConvertTo-TmuxWorkspace -ErrorAction Stop |
    ConvertTo-TmuxWorkspaceYaml -ErrorAction Stop |
    Set-Content -LiteralPath $exportPath -Encoding utf8NoBOM -ErrorAction Stop
```

- Conversion keeps session-relative window indices.
- It warns because it omits observed options, environment, terminal text, entity
  IDs, pane indices and shared-link identity, and cannot rebuild original startup
  commands or shell intent.
- Repeated window links become separate declarations.
- Check the layout and pane paths, add the commands you want on a later load,
  then import, resolve and review a new plan.
- For JSON, use `ConvertTo-TmuxWorkspaceJson` instead of the YAML converter.

See [ConvertTo-TmuxWorkspace](reference/LibTmux.Workspace/ConvertTo-TmuxWorkspace.md)
for the captured-field and literal-path rules.

## Edit the declaration

Choose a file and an installed editor yourself.

- `$workspaceFile` is the `FileInfo` from `Get-TmuxWorkspace`.
- `$editor` is an `ApplicationInfo`, for example from
  `Get-Command -Name nvim -CommandType Application -ErrorAction Stop`.
- `[string[]] $editorArguments = @()` means no extra arguments. A GUI editor that
  returns at once needs its own wait option, such as `@('--wait')`.

Run it as a foreground command in your terminal, without assigning, piping or
redirecting its output. The file's absolute path is one argument, and arguments
pass separately, including spaces, quotes and empty strings.

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

- A nonzero editor exit stops the block with that code, and launch errors stop it
  too. Exit the editor normally when finished.
- Ctrl+C follows the editor's and terminal's usual behavior, and some editors
  treat it as an editing command and stay open.
- The recipe has no `-WhatIf`, forced stop or process-tree cleanup, and it does
  not undo saved edits.
- Editing runs no workspace command or tmux operation. Afterward, import,
  resolve, validate and review a new plan. An existing plan keeps the
  declaration it was created from.

## Type a command without submitting it

`enter: false` prepares input for review. This example creates a shell, reads the
pending command, submits one Enter and waits for the rendered output. The result
holds the reviewed plan, the pending text and the completion. The `finally`
block removes its session.

<!-- example: workspace.10-pending -->
```powershell
& {
    $ErrorActionPreference = 'Stop'
    $declaration = Import-TmuxWorkspace -Yaml @'
session_name: review-command
options:
  default-command: exec /bin/sh
windows:
  - window_name: review
    panes:
      - shell_command:
          - cmd: "printf '\\nreview %s\\n' complete"
            enter: false
'@
    $plan = $declaration | Get-TmuxWorkspacePlan -Server $server
    $result = $null
    try {
        $result = $plan | Invoke-TmuxWorkspace -Confirm:$false
        $pane = $result.Windows[0].Panes[0]
        $typed = "printf '\nreview %s\n' complete"
        $wait = @{ Timeout = 10; Confirm = $false }
        $pending = $pane |
            Wait-TmuxPaneText -Pattern $typed -SimpleMatch @wait
        if ($pending.Outcome -notin 'PresentAtEntry', 'Matched') {
            throw "Pending input wait ended with $($pending.Outcome)."
        }
        $pane | Send-TmuxKey -Key Enter -Confirm:$false
        $completion = $pane |
            Wait-TmuxPaneText -Pattern '^review complete$' @wait
        if ($completion.Outcome -notin 'PresentAtEntry', 'Matched') {
            throw "Pending command wait ended with $($completion.Outcome)."
        }
        [pscustomobject]@{
            Pending = $pending.Tail -join "`n"
            Completion = $completion
            Plan = $plan
        }
    } finally {
        if ($result) { $result.Session | Remove-TmuxSession -Confirm:$false }
    }
}
```

## Startup, host effects and failures

### Readiness

- **`-Readiness Immediate`:** sends configured commands as literal input,
  applying each command's Enter setting. It does not infer shell readiness or
  command completion.
- **`-Readiness Cooperative`:** pane startup receives a fresh
  `LIBTMUX_WORKSPACE_READY` channel and must signal it when it can accept input,
  using the selected tmux executable and the same server:
  `tmux wait-for -S "$LIBTMUX_WORKSPACE_READY"`. A signal sent before the wait is
  kept. `-ReadinessTimeout` bounds each wait in seconds. A sent command's
  completion needs its own application signal.

See the
[shared engine's cooperative startup example](https://github.com/libtmux/libtmux-dotnet/blob/master/src/LibTmux.Workspace/README.md#readiness-and-existing-sessions).

### Host scripts

A declaration's `before_script` runs on the host only when planning admits it
with `-AllowHostScripts`. Review host scripts and pane commands before applying a
file from another source.

- Resolve the document first.
- Creation and replacement run the script after the named session exists. Append
  uses the existing session, and Reuse skips the script.
- The working directory is the resolved session `start_directory`, falling back
  to the document directory.
- The script is literal shell text passed to `/bin/sh -c`; tmuxp's rewrite of a
  leading `./script` path does not apply.
- Give `Test-TmuxWorkspace` and `Get-TmuxWorkspacePlan` the same policy,
  including `-HostScriptTimeout` and `-MaxHostOutputBytes` if you change their
  bounds. Invocation uses those frozen settings.
- Validation, planning and `-WhatIf` never run the script.

### Failures

Application failures write
[`Tmux.WorkspaceApplyFailed`][invoketmuxworkspacecommand] with a
[`WorkspaceBuildException`][workspacebuildexception] and emit no partial success
object.

- With `-ErrorAction Stop`, a `catch` block can read
  [`$_.Exception`][system-management-automation-errorrecord-exception] for
  `.PartialResult`, `.Journal`, `.CompensationJournal`, `.Dispatch` and
  `.InnerException`.
- With normal error handling, later plans continue.
- A stopped PowerShell pipeline may suppress error delivery, so do not count on a
  journal after stopping it.

This example appends a window to the `development` session built above, then
asks tmux to set an invalid pane option. It requests compensation for the new
window, and the existing session and its `editor` window are borrowed and must
remain. Run it only against the session this guide created.

<!-- example: workspace.09-recover -->
```powershell
$workspaceRecovery = & {
    $broken = Import-TmuxWorkspace -Yaml @'
session_name: development
windows:
  - window_name: recovery-demo
    panes:
      - options:
          libtmux-invalid-option: fail
'@ -ErrorAction Stop
    $plan = $broken | Get-TmuxWorkspacePlan -Server $server `
        -ExistingSession Append -ServerStartup RequireExisting `
        -CompensateOnFailure -ErrorAction Stop
    try {
        $null = $plan | Invoke-TmuxWorkspace -Confirm:$false -ErrorAction Stop
        throw 'The deliberately invalid option was accepted.'
    } catch {
        $type = [LibTmux.Workspace.WorkspaceBuildException]
        if ($_.Exception -isnot $type) { throw }
        $failure = $_.Exception
    }
    [pscustomobject]@{
        Plan = $plan
        Failure = $failure
        Current = ($server | Get-TmuxSnapshot -Depth Panes -ErrorAction Stop)
    }
}
```

Read the result in this order:

1. [`$workspaceRecovery.Failure.Journal`][workspacebuildexception-journal] shows
   the failed action and its dispatch state.
2. [`$workspaceRecovery.Failure.CompensationJournal`][workspacebuildexception-compensationjournal]
   shows attempted cleanup.
3. The fresh [`$workspaceRecovery.Current.Sessions`][server-sessions] shows what
   remains. A completed cleanup entry records a tmux operation, and the
   observation proves whether `recovery-demo` is gone and `editor` remains.

If dispatch is `Unknown` or cleanup failed, the action may have taken effect.
Inspect the server and reconcile it before making another plan; do not retry the
same plan blindly.

- `-CompensateOnFailure` at planning requests bounded cleanup of creations whose
  ownership this application proves. Review
  [`$workspacePlan.CompensationActions`][workspaceplan-compensationactions] too.
- `-CleanupTimeout` bounds cleanup. It cannot undo shell or host side effects.
- The module never owns a borrowed daemon and never guesses cleanup targets from
  names.

The declaration format covers session, window and pane options, global session
defaults, post-construction window options, layouts, focus, environment,
directory inheritance and command lists. Unsupported keys are errors. For the
policy parameters, see
[Get-TmuxWorkspacePlan](reference/LibTmux.Workspace/Get-TmuxWorkspacePlan.md) and
[Invoke-TmuxWorkspace](reference/LibTmux.Workspace/Invoke-TmuxWorkspace.md).

[workspaceserverstartup-createorjoin]: https://libtmux.org/en/csharp/latest/workspace/reference/libtmux-workspace-workspaceserverstartup-createorjoin/
[workspaceserverstartup-requireexisting]: https://libtmux.org/en/csharp/latest/workspace/reference/libtmux-workspace-workspaceserverstartup-requireexisting/
[workspaceaction-request]: https://libtmux.org/en/csharp/latest/workspace/reference/libtmux-workspace-workspaceaction-request/
[workspaceplan-compensationactions]: https://libtmux.org/en/csharp/latest/workspace/reference/libtmux-workspace-workspaceplan-compensationactions/
[workspaceactionkind-captureresult]: https://libtmux.org/en/csharp/latest/workspace/reference/libtmux-workspace-workspaceactionkind-captureresult/
[workspaceresult-session]: https://libtmux.org/en/csharp/latest/workspace/reference/libtmux-workspace-workspaceresult-session/
[workspaceexistingsession-reuse]: https://libtmux.org/en/csharp/latest/workspace/reference/libtmux-workspace-workspaceexistingsession-reuse/
[workspaceexistingsession-append]: https://libtmux.org/en/csharp/latest/workspace/reference/libtmux-workspace-workspaceexistingsession-append/
[workspaceexistingsession-replace]: https://libtmux.org/en/csharp/latest/workspace/reference/libtmux-workspace-workspaceexistingsession-replace/
[invoketmuxworkspacecommand]: ../src/LibTmux.Workspace.PowerShell/InvokeTmuxWorkspaceCommand.cs
[workspacebuildexception]: https://libtmux.org/en/csharp/latest/workspace/reference/libtmux-workspace-workspacebuildexception/
[system-management-automation-errorrecord-exception]: https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.errorrecord.exception?view=powershellsdk-7.4.0
[workspacebuildexception-journal]: https://libtmux.org/en/csharp/latest/workspace/reference/libtmux-workspace-workspacebuildexception-journal/
[workspacebuildexception-compensationjournal]: https://libtmux.org/en/csharp/latest/workspace/reference/libtmux-workspace-workspacebuildexception-compensationjournal/
[server-sessions]: https://libtmux.org/en/csharp/latest/reference/libtmux-server-sessions/
