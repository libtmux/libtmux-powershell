---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Get-TmuxSnapshot.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/19/2026
PlatyPS schema version: 2024-05-01
title: Get-TmuxSnapshot
---

# Get-TmuxSnapshot

## SYNOPSIS

Capture a replacement tmux hierarchy.

## SYNTAX

### __AllParameterSets

```text
Get-TmuxSnapshot [-Server] <Server> [-Depth <SnapshotDepth>]
```

## ALIASES

None.

## DESCRIPTION

Read the explicit server endpoint to the requested Depth. The default Panes depth captures sessions, contextual windows and panes. Shallower snapshots leave deeper relations unavailable. The input handle and previous captures remain unchanged.

## EXAMPLES

### Example 1

Capture the hierarchy of the existing server identified by $SocketPath.

```powershell
LibTmux\New-TmuxServer -SocketPath $SocketPath | LibTmux\Get-TmuxSnapshot -Depth Panes
```

## PARAMETERS

### -Depth

The deepest hierarchy level to capture.

```yaml
Type: LibTmux.SnapshotDepth
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

The server to read.

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

### LibTmux.Server

Native pipeline type for this command.

## NOTES

Acquisition spans multiple tmux commands and does not promise an atomic view. Property access uses captured data; unavailable relations throw rather than appearing empty.

## RELATED LINKS

[Task guide](../../read.md)
