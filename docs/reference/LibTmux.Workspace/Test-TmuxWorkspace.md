---
document type: cmdlet
external help file: LibTmux.Workspace.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux.Workspace/Test-TmuxWorkspace.md
Locale: en-US
Module Name: LibTmux.Workspace
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: Test-TmuxWorkspace
---

# Test-TmuxWorkspace

## SYNOPSIS

Validate a workspace declaration and its intended policies locally.

## SYNTAX

### __AllParameterSets

```text
Test-TmuxWorkspace [-Workspace] <WorkspaceFile> [-ExistingSession <WorkspaceExistingSession>] [-ServerStartup <WorkspaceServerStartup>] [-Readiness <WorkspaceReadiness>] [-ReadinessTimeout <Double>] [-CompensateOnFailure] [-AllowHostScripts] [-HostScriptTimeout <Double>] [-MaxHostOutputBytes <Int32>] [-CleanupTimeout <Double>]
```

## ALIASES

None.

## DESCRIPTION

Apply the shared .NET declaration and policy checks to a native WorkspaceFile.
Validation reads no tmux state and executes no commands or scripts. Importing a
workspace checks syntax; this command additionally rejects incomplete or invalid
declarations under the supplied policy.

Validation returns True on success. An invalid declaration writes its native
error and returns False; ErrorAction Stop terminates instead. Invalid policy
parameters terminate before processing input.

Local validation does not check endpoint conflicts, paths on disk, shell syntax
or tmux option support. Reuse defers host-script admission until planning knows
whether creation is needed. Use Get-TmuxWorkspacePlan for endpoint observation
and a reviewable plan; the validation result is not permission to apply it.

## EXAMPLES

### Example 1

Check a one-window declaration without opening a tmux connection.

```powershell
LibTmux.Workspace\Import-TmuxWorkspace -Yaml @'
session_name: development
windows:
  - panes: [null]
'@ | LibTmux.Workspace\Test-TmuxWorkspace
```

## PARAMETERS

### -Workspace

The immutable declaration to check.

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

### -ExistingSession

Reuse defers host-script admission until planning determines whether creation is necessary.

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

The startup policy intended for planning; validation does not inspect the endpoint.

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

The declared startup contract; validation does not wait for or prove shell readiness.

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

A finite positive readiness budget in seconds, at most 86400.

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

Validate the policy that permits compensation of journal-owned creations after application failure.

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

Admit declared host scripts for planning. Validation never executes them.

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

A finite positive host-script budget in seconds, at most 86400.

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

A positive combined stdout and stderr capture limit in UTF-8 bytes.

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

A finite positive application cleanup budget in seconds, at most 86400.

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

A parsed or programmatically constructed declaration.

## OUTPUTS

### System.Boolean

True for a valid declaration; False after a nonterminating validation error.

## NOTES

Tmux.WorkspaceValidationFailed retains the native exception and declaration. Tmux.InvalidWorkspacePolicy identifies invalid policy parameters.

## RELATED LINKS

[Import-TmuxWorkspace](Import-TmuxWorkspace.md)

[Get-TmuxWorkspacePlan](Get-TmuxWorkspacePlan.md)
