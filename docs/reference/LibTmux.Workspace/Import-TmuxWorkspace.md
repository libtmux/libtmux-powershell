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

### Yaml

```text
Import-TmuxWorkspace -Yaml <string>
```

## ALIASES

None.

## DESCRIPTION

Read a literal file path or parse supplied YAML text into a native WorkspaceFile. Parsing does not start tmux, send shell commands or execute host scripts. This command accepts the current shared engine subset; complete plan/apply is still under development.

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

### -Yaml

Yaml declaration text.

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

## OUTPUTS

### LibTmux.Workspace.WorkspaceFile

Native pipeline type for this command.

## NOTES

LiteralPath reads the specified file without wildcard expansion. Yaml accepts declaration text. Neither form is a workspace loader.

## RELATED LINKS

[Task guide](../../read.md)
