---
document type: cmdlet
external help file: LibTmux.Workspace.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux.Workspace/Invoke-TmuxWorkspace.md
Locale: en-US
Module Name: LibTmux.Workspace
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: Invoke-TmuxWorkspace
---

# Invoke-TmuxWorkspace

## SYNOPSIS

Apply the exact workspace plan after one confirmation.

## SYNTAX

### __AllParameterSets

```text
Invoke-TmuxWorkspace [-Plan] <WorkspacePlan> [-WhatIf] [-Confirm]
```

## ALIASES

None.

## DESCRIPTION

Apply the supplied native WorkspacePlan using its own endpoint, observed
identities and frozen actions. No declaration, file, endpoint or policy can be
substituted at invocation. Stale preconditions fail; invocation never replans or
retries mutations automatically.

One PowerShell ShouldProcess decision covers the whole plan. Its target names
the executable, socket and literal session name. Its action describes conflict,
startup, readiness and compensation policy, host execution, planned effect
kinds and conditional cleanup. Inspect the original plan for full request and
host-command values. WhatIf and declined confirmation perform no application
I/O or cleanup and emit no WorkspaceResult.

Successful invocation returns one native WorkspaceResult containing the session,
created windows, unsupported layouts and action journals. WorkspaceBuildException
remains ErrorRecord.Exception under Tmux.WorkspaceApplyFailed, with the original
plan as TargetObject. Inspect its Dispatch, InnerException, PartialResult,
Journal and CompensationJournal; partial results are never emitted as success.

Stopping the pipeline cancels owned work. Cleanup follows the plan's frozen
budget. A stopped pipeline can suppress subsequent error output, so receiving a
cancellation journal after pipeline shutdown is not guaranteed. Application is
detached; it does not attach a terminal or transfer ownership of the daemon.
To enter the applied session, pass the successful WorkspaceResult.Session to
Enter-TmuxSession in a foreground terminal outside tmux. Attachment has its own
confirmation and cancellation behavior; it does not repeat application.

## EXAMPLES

### Example 1

Preview an existing plan created by Get-TmuxWorkspacePlan without applying it.

```powershell
$Plan | LibTmux.Workspace\Invoke-TmuxWorkspace -WhatIf
```

### Example 2

Apply that reviewed plan with the normal confirmation explicitly disabled.

```powershell
$Plan | LibTmux.Workspace\Invoke-TmuxWorkspace -Confirm:$false
```

## PARAMETERS

### -Plan

The exact native plan to apply. Its endpoint, actions, creation identity checks and cleanup policies are preserved.

```yaml
Type: LibTmux.Workspace.WorkspacePlan
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

### -WhatIf

Describe the whole plan without tmux inspection, host execution, mutation or cleanup. No success object is returned.

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

### -Confirm

Request normal PowerShell confirmation for the whole reviewed plan. The command has High confirmation impact.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### LibTmux.Workspace.WorkspacePlan

A native plan prepared by Get-TmuxWorkspacePlan or the shared .NET API.

## OUTPUTS

### LibTmux.Workspace.WorkspaceResult

One completed native result. Preview and declined confirmation emit nothing.

## NOTES

Replace is an explicit planning policy. Compensation can remove only creations
whose ownership is established by the native journal; shell and host-script
effects cannot be undone. Reuse returns the existing session without running
workspace mutation or host actions.

## RELATED LINKS

[Get-TmuxWorkspacePlan](Get-TmuxWorkspacePlan.md)

[Enter-TmuxSession](../LibTmux/Enter-TmuxSession.md)
