---
document type: cmdlet
external help file: LibTmux.Workspace.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux.Workspace/Get-TmuxWorkspacePlan.md
Locale: en-US
Module Name: LibTmux.Workspace
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: Get-TmuxWorkspacePlan
---

# Get-TmuxWorkspacePlan

## SYNOPSIS

Observe an explicit endpoint and prepare a workspace plan.

## SYNTAX

### __AllParameterSets

```text
Get-TmuxWorkspacePlan [-Workspace] <WorkspaceFile> -Server <Server> [-ExistingSession <WorkspaceExistingSession>] [-ServerStartup <WorkspaceServerStartup>] [-Readiness <WorkspaceReadiness>] [-ReadinessTimeout <Double>] [-CompensateOnFailure] [-AllowHostScripts] [-HostScriptTimeout <Double>] [-MaxHostOutputBytes <Int32>] [-CleanupTimeout <Double>]
```

## ALIASES

None.

## DESCRIPTION

Validate the native declaration and policies, then inspect the supplied tmux
endpoint. Return one native WorkspacePlan containing ordered actions, native
requests and observed identity preconditions. Planning does not start a daemon,
create panes, send commands or execute the declaration's host script.

Resolve file-relative paths explicitly before planning. Host scripts require a
resolved document directory and AllowHostScripts when they will execute. The
plan freezes the chosen policies, host limits and command arguments. Review its
Actions and CompensationActions, then pass that same plan to
Invoke-TmuxWorkspace. Changing a source file does not change an existing plan.

Error refuses a conflicting session. Reuse plans only reuse when that session
exists, skipping declaration effects and host execution. Append creates declared
windows while preserving existing session settings. Replace selects the exact
observed session for replacement. A stale plan fails at application; it is not
automatically regenerated.

Observation spans tmux operations and is not a transaction. Native options,
layouts, hooks and configuration can still cause application failures.

## EXAMPLES

### Example 1

Plan a workspace at an explicit socket without creating its session.

```powershell
LibTmux.Workspace\Import-TmuxWorkspace -Yaml '{"session_name":"development","windows":[{"window_name":"editor"}]}' | LibTmux.Workspace\Get-TmuxWorkspacePlan -Server (LibTmux\New-TmuxServer -SocketPath $SocketPath)
```

## PARAMETERS

### -Workspace

The immutable parsed declaration. Resolve paths explicitly before planning when they depend on a document directory.

```yaml
Type: LibTmux.Workspace.WorkspaceFile
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Server

The explicit endpoint to inspect. Planning borrows its lifetime and never initializes an absent daemon.

```yaml
Type: LibTmux.Server
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ExistingSession

Choose Error, Reuse, Append or Replace for a session with the same literal name. Replace is frozen into the plan; invocation uses normal PowerShell confirmation.

```yaml
Type: LibTmux.Workspace.WorkspaceExistingSession
DefaultValue: 'Error'
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: [Error, Reuse, Append, Replace]
HelpMessage: ''
```

### -ServerStartup

CreateOrJoin allows later application to start or join an initially absent daemon. RequireExisting fails planning when no daemon is present. Neither choice grants daemon ownership.

```yaml
Type: LibTmux.Workspace.WorkspaceServerStartup
DefaultValue: 'CreateOrJoin'
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: [CreateOrJoin, RequireExisting]
HelpMessage: ''
```

### -Readiness

Immediate sends input without claiming shell readiness or command completion. Cooperative requires pane startup to signal the channel named by LIBTMUX_WORKSPACE_READY.

```yaml
Type: LibTmux.Workspace.WorkspaceReadiness
DefaultValue: 'Immediate'
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: [Immediate, Cooperative]
HelpMessage: ''
```

### -ReadinessTimeout

Each cooperative signal budget in seconds. Accepts finite values from 0.0000001 through 86400.

```yaml
Type: System.Double
DefaultValue: '10'
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -CompensateOnFailure

Attempt cleanup of journal-proven creations after failure. Shell input and host-script effects are irreversible. Owned readiness channels and replacement keepalives have mandatory cleanup regardless of this switch.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: 'False'
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -AllowHostScripts

Allow a declared before_script to become a native RunHostScript action. Planning does not execute it. Reuse skips it when the existing session can be reused.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: 'False'
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -HostScriptTimeout

The host script deadline, including output collection, in seconds. Accepts finite values from 0.0000001 through 86400.

```yaml
Type: System.Double
DefaultValue: '30'
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -MaxHostOutputBytes

The positive combined stdout and stderr capture limit in UTF-8 bytes. Additional output is drained and its dropped byte count remains visible in the native host result.

```yaml
Type: System.Int32
DefaultValue: '1048576'
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -CleanupTimeout

The total failure-cleanup budget in seconds. Accepts finite values from 0.0000001 through 86400. Incomplete or uncertain cleanup remains visible in the native journal.

```yaml
Type: System.Double
DefaultValue: '1'
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### LibTmux.Workspace.WorkspaceFile

A parsed declaration, optionally resolved against an explicit document directory.

## OUTPUTS

### LibTmux.Workspace.WorkspacePlan

The native immutable plan with its endpoint and ordered actions.

## NOTES

All numeric timeout parameters use seconds. Policy validation occurs before
endpoint observation. Planning errors preserve the native exception with the
Tmux.WorkspacePlanFailed identifier; invalid policy values use
Tmux.InvalidWorkspacePolicy.

## RELATED LINKS

[Invoke-TmuxWorkspace](Invoke-TmuxWorkspace.md)
[Import-TmuxWorkspace](Import-TmuxWorkspace.md)
