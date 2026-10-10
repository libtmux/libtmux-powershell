---
document type: cmdlet
external help file: LibTmux.PowerShell.dll-Help.xml
HelpUri: https://github.com/libtmux/libtmux-powershell/blob/master/docs/reference/LibTmux/Get-TmuxServer.md
Locale: en-US
Module Name: LibTmux
ms.date: 09/20/2026
PlatyPS schema version: 2024-05-01
title: Get-TmuxServer
---

# Get-TmuxServer

## SYNOPSIS

Inspect an existing tmux daemon's identity and version.

## SYNTAX

### __AllParameterSets

```text
Get-TmuxServer [-Server] <Server>
```

## ALIASES

None.

## DESCRIPTION

Read the selected endpoint and return a native Server with its daemon generation
and DaemonVersion. An absent daemon produces no output. Inspection never starts
a daemon and leaves the input handle unchanged.

Sessions, windows and panes remain uncaptured. Pipe the inspected server to
Get-TmuxSnapshot to acquire those relationships and retain the inspected version
for Get-TmuxQueryPlan.

## EXAMPLES

### Example 1

Inspect the existing daemon identified by $SocketPath.

```powershell
LibTmux\New-TmuxServer -SocketPath $SocketPath | LibTmux\Get-TmuxServer
```

## PARAMETERS

### -Server

The server endpoint to inspect.

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

Native endpoint handle.

## OUTPUTS

### LibTmux.Server

Inspected daemon, when present.

## NOTES

Tmux.ServerInspectionFailed retains the native exception and target. Inspection
of an absent endpoint is successful and emits no object; other failures use the
error stream. Use ErrorAction Stop to stop the pipeline on those failures.

## RELATED LINKS

[Read tmux state](../../read.md)
[Structured queries](../../query.md)
[Get-TmuxSnapshot](Get-TmuxSnapshot.md)
