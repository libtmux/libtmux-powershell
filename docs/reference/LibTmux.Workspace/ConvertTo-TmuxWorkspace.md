---
document type: cmdlet
external help file: LibTmux.Workspace.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux.Workspace/ConvertTo-TmuxWorkspace.md
Locale: en-US
Module Name: LibTmux.Workspace
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: ConvertTo-TmuxWorkspace
---

# ConvertTo-TmuxWorkspace

## SYNOPSIS

Convert a captured session to a native workspace declaration.

## SYNTAX

```text
ConvertTo-TmuxWorkspace [-Session] <Session>
```

## ALIASES

None.

## DESCRIPTION

Return one native WorkspaceFile for each captured Session received from the
pipeline. The shared library preserves captured window placements and pane order,
names, layouts, active window and pane flags, and pane directories. Repeated links
to the same window become separate declared windows.

Capture with Get-TmuxSnapshot -Depth Panes before selecting a Session. Conversion
never contacts tmux or fills unavailable relations. The captured graph remains
convertible after its daemon exits. A missing field or relation is an error;
a captured null pane directory remains unspecified rather than using the host's
current directory.

Captured directories become unresolved declaration values with literal dollars
escaped as `$$`. DocumentDirectory remains null. Use Resolve-TmuxWorkspace with
an explicit BaseDirectory before planning, or convert the declaration to YAML
or JSON and resolve it after importing. Do not interpret those escaped values
as already resolved filesystem paths.

Conversion emits a warning for each successful input because it omits observed
environment, options, terminal text, entity IDs, indices and shared-link
identity.
It cannot reconstruct original commands, arguments or shell intent. Foreground
command names do not establish the shell command that started a pane. Original
relative paths, expansion variables, comments, host scripts and pre-commands
are not reconstructed. Native custom layouts can change which pane occupies a
position when applied. This declaration
is a starting configuration, not a checkpoint of running programs.

## EXAMPLES

### Example 1

Convert a native Session selected from a pane-depth snapshot. This operation
uses only the supplied capture and does not own resources requiring cleanup.

```powershell
$capturedSession | LibTmux.Workspace\ConvertTo-TmuxWorkspace
```

## PARAMETERS

### -Session

The native session whose window, pane and active-pane relations and required
fields have already been captured. Binding by an arbitrary object's Session
property is not supported.

```yaml
Type: LibTmux.Session
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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### LibTmux.Session

A native captured session; serialized copies are not live native objects.

## OUTPUTS

### LibTmux.Workspace.WorkspaceFile

One unresolved declaration per successfully converted input session.

## NOTES

Tmux.WorkspaceFreezeFailed retains the original native exception and input
Session as its target. IncompleteSnapshotException uses the InvalidData error
category. ErrorAction Continue permits later sessions to be converted without
emitting a declaration for a failed input; ErrorAction Stop terminates.
The loss warning uses PowerShell's warning stream and supports WarningAction.
The command performs no acquisition, execution or file write and has no WhatIf
or Confirm parameters.

## RELATED LINKS

[Get-TmuxSnapshot](../LibTmux/Get-TmuxSnapshot.md)

[Resolve-TmuxWorkspace](Resolve-TmuxWorkspace.md)

[ConvertTo-TmuxWorkspaceYaml](ConvertTo-TmuxWorkspaceYaml.md)

[ConvertTo-TmuxWorkspaceJson](ConvertTo-TmuxWorkspaceJson.md)
