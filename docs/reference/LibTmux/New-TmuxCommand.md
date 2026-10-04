---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/New-TmuxCommand.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: New-TmuxCommand
---

# New-TmuxCommand

## SYNOPSIS

Construct a native tmux command without running it.

## SYNTAX

### __AllParameterSets

```text
New-TmuxCommand [-Name] <String> [[-Arguments] <String[]>]
```

## ALIASES

None.

## DESCRIPTION

Create one native TmuxCommand with literal argument boundaries. Construction
performs no tmux I/O, starts no shell and copies the supplied string array.
Empty strings remain arguments; null and NUL-containing arguments are rejected.

Use this value with Invoke-TmuxChain or Invoke-TmuxControlCommand. Values
returned by native typed requests can be passed directly to those commands;
reconstructing a typed request as raw text would discard its identity guards.

## EXAMPLES

### Example 1

Construct a command that prints text containing spaces and punctuation.

```powershell
LibTmux\New-TmuxCommand -Name 'display-message' -Arguments @(
    '-p', 'hello; tmux'
)
```

## PARAMETERS

### -Arguments

Literal command arguments. The default is an empty array.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 1
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Name

A tmux command name or alias. Empty, whitespace, NUL and leading global options are rejected.

```yaml
Type: System.String
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
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

### None

No pipeline input.

## OUTPUTS

### LibTmux.TmuxCommand

A native command value; no execution result.

## NOTES

Tmux.InvalidCommand terminates invalid construction before any tmux I/O.

## RELATED LINKS

[Commands and control clients](../../commands.md)
