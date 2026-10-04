---
document type: cmdlet
external help file: LibTmux.Workspace.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux.Workspace/ConvertTo-TmuxWorkspaceYaml.md
Locale: en-US
Module Name: LibTmux.Workspace
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: ConvertTo-TmuxWorkspaceYaml
---

# ConvertTo-TmuxWorkspaceYaml

## SYNOPSIS

Convert a native workspace declaration to YAML text.

## SYNTAX

```text
ConvertTo-TmuxWorkspaceYaml [-Workspace] <WorkspaceFile>
```

## ALIASES

None.

## DESCRIPTION

Return one string for each native WorkspaceFile received from the pipeline.
The text uses the snake_case keys accepted by Import-TmuxWorkspace and the
native parser. Conversion preserves pane and command order, empty strings,
nullable fields, local options, environment and commands at every declaration
level. It does not expand command text or inherit local defaults into children.

Resolved directories contain literal paths. Conversion escapes their dollar
signs as `$$` so export, import and a later explicit Resolve-TmuxWorkspace keep
the same paths. Unresolved variable expressions remain unchanged.
DocumentDirectory is resolution provenance and is omitted from the text;
provide an explicit base when resolving the imported declaration.

The native parser checks emitted text, including its character limit. This is
not application validation: incomplete declarations can still be converted.
No tmux observation, command execution, file writing or plan serialization
occurs. Formatting and comments from an imported source document are not part
of the native declaration and are not reproduced.

## EXAMPLES

### Example 1

Convert a two-pane declaration for storage or inspection.

```powershell
LibTmux.Workspace\Import-TmuxWorkspace -Yaml @'
session_name: development
windows:
  - window_name: work
    panes: [nvim, ""]
'@ | LibTmux.Workspace\ConvertTo-TmuxWorkspaceYaml
```

## PARAMETERS

### -Workspace

The native declaration to serialize without applying it.

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

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### LibTmux.Workspace.WorkspaceFile

A parsed or explicitly resolved declaration.

## OUTPUTS

### System.String

One YAML document per input declaration.

## NOTES

Serialization errors terminate with Tmux.WorkspaceYamlFailed and retain the
original exception. Null host commands are omitted because the native parser
rejects an explicit null before_script. Nullable name and directory values
remain distinct from empty strings. The native model does not retain a
distinction between omitted and empty collections or omitted and false focus.

## RELATED LINKS

[Import-TmuxWorkspace](Import-TmuxWorkspace.md)

[Resolve-TmuxWorkspace](Resolve-TmuxWorkspace.md)

[ConvertTo-TmuxWorkspaceJson](ConvertTo-TmuxWorkspaceJson.md)
