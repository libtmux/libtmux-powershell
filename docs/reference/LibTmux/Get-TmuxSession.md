---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Get-TmuxSession.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/19/2026
PlatyPS schema version: 2024-05-01
title: Get-TmuxSession
---

# Get-TmuxSession

## SYNOPSIS

Read sessions with optional exact selectors.

## SYNTAX

### __AllParameterSets

```text
Get-TmuxSession [-Server] <Server> [-Id <string>] [-Name <string>]
```

## ALIASES

None.

## DESCRIPTION

Acquire sessions from a native Server. Id and Name are ordinal, case-sensitive literal selectors; combining them requires both to match. Wildcards are not expanded. An unmatched selector emits nothing; a failed acquisition writes an error.

## EXAMPLES

### Example 1

List sessions on the existing server identified by $SocketPath.

```powershell
LibTmux\New-TmuxServer -SocketPath $SocketPath | LibTmux\Get-TmuxSession
```

## PARAMETERS

### -Id

An ordinal, literal session identifier selector.

```yaml
Type: System.String
DefaultValue: ''
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

### -Name

An ordinal, literal session name selector.

```yaml
Type: System.String
DefaultValue: ''
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

### -Server

The server whose sessions are read.

```yaml
Type: LibTmux.Server
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

### LibTmux.Server

Native pipeline type for this command.

## OUTPUTS

### LibTmux.Session

Native pipeline type for this command.

## NOTES

Wrap results in @() when a stable array is needed. A missing daemon is an error, not a successful empty list. Session-only capture does not acquire windows.

## RELATED LINKS

[Task guide](../../read.md)
