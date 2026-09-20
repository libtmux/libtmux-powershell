---
document type: cmdlet
external help file: LibTmux.Workspace.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux.Workspace/Import-TmuxWorkspace.md
Locale: en-US
Module Name: LibTmux.Workspace
ms.date: 09/19/2026
PlatyPS schema version: 2024-05-01
title: Import-TmuxWorkspace
---

# Import-TmuxWorkspace

## SYNOPSIS

Parse a workspace declaration without executing it.

## SYNTAX

### Path (Default)

```text
Import-TmuxWorkspace [-LiteralPath] <string>
```

### File

```text
Import-TmuxWorkspace -File <FileInfo>
```

### Yaml

```text
Import-TmuxWorkspace -Yaml <string>
```

## ALIASES

None.

## DESCRIPTION

Read a literal filesystem path, a FileInfo pipeline or supplied YAML/JSON text
into a native WorkspaceFile. Inputs must be seekable UTF-8 files; a UTF-8 BOM
is accepted. Named pipes are rejected without waiting for a writer.
Admission stops at 1048576 characters, before retaining an oversized document.
Malformed YAML/JSON and invalid UTF-8 preserve their exceptions as InvalidData
errors.

Parsing does not start tmux, execute host scripts or expand paths and variables.
Resolve-TmuxWorkspace supplies an explicit document base and allowed variables.
Test-TmuxWorkspace checks declaration completeness and execution policy.

## EXAMPLES

### Example 1

Inspect a declaration without executing it.

```powershell
LibTmux.Workspace\Import-TmuxWorkspace -Yaml 'session_name: development'
```

## PARAMETERS

### -LiteralPath

The literal file path to read.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Path
  Position: 0
  IsRequired: true
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -File

A FileInfo returned by Get-Item or workspace discovery. Its path is literal.

```yaml
Type: System.IO.FileInfo
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: File
  Position: Named
  IsRequired: true
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Yaml

YAML or JSON declaration text.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: Yaml
  Position: Named
  IsRequired: true
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

### System.IO.FileInfo

A file to read and parse.

## OUTPUTS

### LibTmux.Workspace.WorkspaceFile

Native pipeline type for this command.

## NOTES

File errors retain Tmux.InvalidWorkspace and allow later pipeline files with
ErrorAction Continue. ErrorAction Stop terminates. No form applies a workspace.

## RELATED LINKS

[Resolve-TmuxWorkspace](Resolve-TmuxWorkspace.md)

[Test-TmuxWorkspace](Test-TmuxWorkspace.md)
